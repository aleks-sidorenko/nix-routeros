{
  # deadnix: skip
  lib,
  terranix,
  system,
  self,
  nixpkgs,
}:
let
  # Not a test (runTests only runs test* names); exposed for module tests.
  render =
    modules:
    (terranix.lib.evalTerranixConfiguration {
      inherit system;
      modules = [ self.terranixModules.default ] ++ modules;
    }).config;
  # Module-level config, for options that never reach the rendered output.
  evalConfig =
    modules:
    (lib.evalModules {
      modules = [
        {
          imports = [
            "${terranix}/core/terraform-options.nix"
            "${terranix}/modules"
          ];
        }
        self.terranixModules.default
      ]
      ++ modules;
      specialArgs.pkgs = nixpkgs.legacyPackages.${system};
    }).config;
  # True when evaluating the rendered output throws (a failed _checks entry).
  fails = modules: !(builtins.tryEval (builtins.deepSeq (render modules) true)).success;
  base = {
    routeros = {
      device = "hap-ax3";
      lan = {
        address = "10.0.0.1/24";
        dhcp.pool = "10.0.0.100-10.0.0.250";
      };
      connection = {
        address = "10.0.0.1";
        username = "admin";
      };
    };
  };
  inherit (self.lib)
    parseCidr
    ipInCidr
    ipInRange
    sanitizeName
    ;
in
{
  inherit render;

  testDeviceNamed = {
    expr =
      (evalConfig [
        {
          routeros.device = "hap-ax3";
        }
      ]).routeros._device.wifi.stack;
    expected = "wifi";
  };
  testDeviceAttrs = {
    expr =
      (evalConfig [
        {
          routeros.device = self.lib.devices.hap-ac2;
        }
      ]).routeros._device;
    expected = self.lib.devices.hap-ac2;
  };

  testParseCidr24 = {
    expr = parseCidr "10.0.0.1/24";
    expected = {
      address = "10.0.0.1";
      prefix = 24;
      network = "10.0.0.0";
    };
  };
  testParseCidr16 = {
    expr = (parseCidr "172.16.5.1/16").network;
    expected = "172.16.0.0";
  };
  testParseCidr20 = {
    expr = (parseCidr "192.168.37.9/20").network;
    expected = "192.168.32.0";
  };
  testIpInCidr = {
    expr = [
      (ipInCidr "10.0.0.10" "10.0.0.0/24")
      (ipInCidr "10.0.1.10" "10.0.0.0/24")
    ];
    expected = [
      true
      false
    ];
  };
  testIpInRange = {
    expr = [
      (ipInRange "10.0.0.120" "10.0.0.100-10.0.0.250")
      (ipInRange "10.0.0.250" "10.0.0.100-10.0.0.250")
      (ipInRange "10.0.0.99" "10.0.0.100-10.0.0.250")
    ];
    expected = [
      true
      true
      false
    ];
  };
  testSanitize = {
    expr = sanitizeName "1c-key";
    expected = "_1c_key";
  };
  testParseCidrMalformedFails = {
    expr = map (c: (builtins.tryEval (parseCidr c).prefix).success) [
      "10.0.0.1"
      "10.0.0.1/33"
      "10.0.0.256/24"
      "10.0.0/24"
    ];
    expected = [
      false
      false
      false
      false
    ];
  };
  testRenderSmoke = {
    expr = (render [ base ]) ? resource;
    expected = true;
  };
  testLanPortsDefault = {
    expr = (evalConfig [ base ]).routeros.lan.ports;
    expected = [
      "ether1"
      "ether2"
      "ether3"
      "ether4"
      "ether5"
    ];
  };
  testLanPortsExcludeUplinkInternal = {
    expr =
      (evalConfig [
        base
        { routeros._uplinkInterfaces = [ "ether2" ]; }
      ]).routeros.lan.ports;
    expected = [
      "ether1"
      "ether3"
      "ether4"
      "ether5"
    ];
  };
  testLeaseRendered = {
    expr =
      (render [
        base
        {
          routeros.lan.leases."my-nas" = {
            mac = "aa:bb:cc:dd:ee:ff";
            address = "10.0.0.20";
          };
        }
      ]).resource.routeros_ip_dhcp_server_lease.my_nas;
    expected = {
      address = "10.0.0.20";
      mac_address = "AA:BB:CC:DD:EE:FF";
      comment = "my-nas";
      server = "lan";
    };
  };
  testProviderNoWifiVar = {
    expr = builtins.attrNames (render [ base ]).variable;
    expected = [
      "routeros_password"
      "routeros_username"
    ];
  };
  testProviderHosturl = {
    expr = (render [ base ]).provider.routeros.hosturl;
    expected = "api://10.0.0.1";
  };
  testLeaseOutsideSubnetFails = {
    expr = fails [
      base
      {
        routeros.lan.leases.far = {
          mac = "aa:bb:cc:dd:ee:ff";
          address = "10.0.1.20";
        };
      }
    ];
    expected = true;
  };
  testLeaseInPoolFails = {
    expr = fails [
      base
      {
        routeros.lan.leases.pooled = {
          mac = "aa:bb:cc:dd:ee:ff";
          address = "10.0.0.120";
        };
      }
    ];
    expected = true;
  };
  testLeaseValidDoesNotFail = {
    expr = fails [
      base
      {
        routeros.lan.leases.ok = {
          mac = "aa:bb:cc:dd:ee:ff";
          address = "10.0.0.20";
        };
      }
    ];
    expected = false;
  };
  testServicesDefaultToSubnet = {
    expr = (render [ base ]).resource.routeros_ip_service.api.address;
    expected = "10.0.0.0/24";
  };
  testLanBridgeAndAddress = {
    expr =
      let
        r = (render [ base ]).resource;
      in
      [
        r.routeros_interface_bridge.bridge.auto_mac
        r.routeros_ip_address.lan.address
        (builtins.attrNames r.routeros_interface_bridge_port)
      ];
    expected = [
      true
      "10.0.0.1/24"
      [
        "ether1"
        "ether2"
        "ether3"
        "ether4"
        "ether5"
      ]
    ];
  };

  testEthernetUplinkRoutes =
    let
      r =
        (render [
          base
          {
            routeros.uplinks.primary = {
              kind = "ethernet";
              check.host = "1.0.0.1";
            };
          }
        ]).resource;
    in
    {
      expr = [
        r.routeros_ip_route.primary_default.distance
        r.routeros_ip_route.primary_default.gateway
        r.routeros_ip_route.primary_default.check_gateway
        r.routeros_ip_route.primary_default.target_scope
        r.routeros_ip_dhcp_client.primary.add_default_route
        r.routeros_ip_dhcp_client.primary.interface
        (lib.hasInfix "1.0.0.1/32" r.routeros_ip_dhcp_client.primary.script)
        (lib.hasInfix "nix-routeros:primary" r.routeros_ip_dhcp_client.primary.script)
        r.routeros_interface_list_member.primary.list
        r.routeros_interface_list.WAN.name
      ];
      expected = [
        1
        "1.0.0.1"
        "ping"
        11
        "no"
        "ether1"
        true
        true
        "WAN"
        "WAN"
      ];
    };
  testLteCheckRoute =
    let
      r =
        (render [
          base
          {
            routeros.uplinks.backup = {
              kind = "lte";
              distance = 2;
              check.host = "9.9.9.9";
              lte.apn = "internet";
            };
          }
        ]).resource;
    in
    {
      expr = [
        r.routeros_ip_route.backup_check
        r.routeros_ip_route.backup_default.distance
        r.routeros_interface_lte_apn.backup.apn
        (r.routeros_ip_dhcp_client or { })
        r.routeros_interface_list_member.backup.interface
      ];
      expected = [
        {
          dst_address = "9.9.9.9/32";
          gateway = "lte1";
          scope = 10;
          comment = "backup";
        }
        2
        "internet"
        { }
        "lte1"
      ];
    };
  testStationUplinkInterface = {
    expr =
      (render [
        base
        {
          routeros.uplinks.hotspot = {
            kind = "wifi-station";
            station.radio = "wifi2";
            check.host = "9.9.9.9";
          };
        }
      ]).resource.routeros_ip_dhcp_client.hotspot.interface;
    expected = "wifi2-station";
  };
  testPppoeVariable = {
    expr =
      let
        c = render [
          base
          {
            routeros.uplinks.dsl = {
              kind = "pppoe";
              check.host = "9.9.9.9";
              pppoe = {
                user = "me";
                passwordVariable = "dsl_password";
              };
            };
          }
        ];
      in
      [
        c.variable.dsl_password.sensitive
        c.resource.routeros_interface_pppoe_client.dsl.password
      ];
    expected = [
      true
      "\${var.dsl_password}"
    ];
  };
  testDuplicateCheckHostFails = {
    expr = fails [
      base
      {
        routeros.uplinks = {
          a = {
            kind = "ethernet";
            check.host = "1.0.0.1";
          };
          b = {
            kind = "lte";
            check.host = "1.0.0.1";
          };
        };
      }
    ];
    expected = true;
  };
  testCheckHostInUpstreamFails = {
    expr = fails [
      base
      {
        routeros.dns.upstream = [ "1.0.0.1" ];
        routeros.uplinks.a = {
          kind = "ethernet";
          check.host = "1.0.0.1";
        };
      }
    ];
    expected = true;
  };
  testLteWithoutUsbFails = {
    expr = fails [
      base
      {
        routeros.device = "hap-ax2";
        routeros.uplinks.a = {
          kind = "lte";
          check.host = "1.0.0.1";
        };
      }
    ];
    expected = true;
  };
  testLanPortsExcludeUplink = {
    expr =
      (evalConfig [
        base
        {
          routeros.uplinks.a = {
            kind = "ethernet";
            interface = "ether2";
            check.host = "1.0.0.1";
          };
        }
      ]).routeros.lan.ports;
    expected = [
      "ether1"
      "ether3"
      "ether4"
      "ether5"
    ];
  };
  testLeaseDuplicateMacFails = {
    expr = fails [
      base
      {
        routeros.lan.leases = {
          a = {
            mac = "aa:bb:cc:dd:ee:ff";
            address = "10.0.0.20";
          };
          b = {
            mac = "AA:BB:CC:DD:EE:FF";
            address = "10.0.0.21";
          };
        };
      }
    ];
    expected = true;
  };
  testLeaseDuplicateAddressFails = {
    expr = fails [
      base
      {
        routeros.lan.leases = {
          a = {
            mac = "aa:bb:cc:dd:ee:01";
            address = "10.0.0.20";
          };
          b = {
            mac = "aa:bb:cc:dd:ee:02";
            address = "10.0.0.20";
          };
        };
      }
    ];
    expected = true;
  };
  testLeaseRouterAddressFails = {
    expr = fails [
      base
      {
        routeros.lan.leases.self = {
          mac = "aa:bb:cc:dd:ee:ff";
          address = "10.0.0.1";
        };
      }
    ];
    expected = true;
  };
  testLeaseChecksWithoutDhcpFail = {
    expr = fails [
      base
      {
        routeros.lan.dhcp.enable = false;
        routeros.lan.leases.far = {
          mac = "aa:bb:cc:dd:ee:ff";
          address = "10.0.1.20";
        };
      }
    ];
    expected = true;
  };
}
