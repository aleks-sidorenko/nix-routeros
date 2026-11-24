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
  wifiHome = {
    routeros.wifi = {
      country = "Latvia";
      networks.home = {
        ssid = "TEST";
        passphraseVariable = "wifi_home";
      };
    };
  };
  station = runtimeManaged: {
    routeros.uplinks.hotspot = {
      kind = "wifi-station";
      station.radio = "wifi2";
      check.host = "9.9.9.9";
      inherit runtimeManaged;
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
        (lib.hasInfix ":local tag \"nix-routeros:primary\"" r.routeros_ip_dhcp_client.primary.script)
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
    expected = "wifi2";
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

  testLteNoUncheckedRoute =
    let
      r =
        (render [
          base
          {
            routeros.uplinks = {
              a = {
                kind = "lte";
                check.host = "9.9.9.9";
                lte.apn = "internet";
              };
              b = {
                kind = "lte";
                interface = "lte2";
                check.host = "9.9.9.8";
              };
            };
          }
        ]).resource;
    in
    {
      expr = [
        (builtins.mapAttrs (_: p: {
          inherit (p) add_default_route use_peer_dns use_network_apn;
          hasApn = p ? apn;
        }) r.routeros_interface_lte_apn)
        (builtins.mapAttrs (_: l: {
          inherit (l) name apn_profiles;
        }) r.routeros_interface_lte)
      ];
      expected = [
        {
          a = {
            add_default_route = false;
            use_peer_dns = false;
            use_network_apn = false;
            hasApn = true;
          };
          b = {
            add_default_route = false;
            use_peer_dns = false;
            use_network_apn = true;
            hasApn = false;
          };
        }
        {
          a = {
            name = "lte1";
            apn_profiles = "a";
          };
          b = {
            name = "lte2";
            apn_profiles = "b";
          };
        }
      ];
    };

  testWifiStackAx3 =
    let
      c = render [
        base
        wifiHome
      ];
      r = c.resource;
    in
    {
      expr = [
        r.routeros_wifi_configuration.home.ssid
        r.routeros_wifi_configuration.home.country
        r.routeros_wifi_configuration.home.mode
        r.routeros_wifi_configuration.home.security.config
        r.routeros_wifi_security.home.passphrase
        r.routeros_wifi_security.home.authentication_types
        r.routeros_wifi.wifi1.configuration.config
        r.routeros_wifi.wifi2.name
        c.variable.wifi_home.sensitive
      ];
      expected = [
        "TEST"
        "Latvia"
        "ap"
        "\${routeros_wifi_security.home.name}"
        "\${var.wifi_home}"
        [
          "wpa2-psk"
          "wpa3-psk"
        ]
        "\${routeros_wifi_configuration.home.name}"
        "wifi2"
        true
      ];
    };
  testWifiSecondNetworkVirtual =
    let
      r =
        (render [
          base
          wifiHome
          {
            routeros.wifi.networks.iot = {
              ssid = "IOT";
              bands = [ "2ghz" ];
              passphraseVariable = "wifi_iot";
            };
          }
        ]).resource;
    in
    {
      expr = [
        (builtins.attrNames r.routeros_wifi)
        r.routeros_wifi.iot_wifi2.master_interface
        r.routeros_wifi.iot_wifi2.name
        r.routeros_wifi.wifi2.configuration.config
      ];
      expected = [
        [
          "iot_wifi2"
          "wifi1"
          "wifi2"
        ]
        "\${routeros_wifi.wifi2.name}"
        "iot-wifi2"
        "\${routeros_wifi_configuration.home.name}"
      ];
    };
  testWirelessStackAc2 =
    let
      r =
        (render [
          base
          wifiHome
          { routeros.device = lib.mkForce "hap-ac2"; }
        ]).resource;
    in
    {
      expr = [
        r.routeros_interface_wireless.wlan1.mode
        r.routeros_interface_wireless.wlan1.ssid
        r.routeros_interface_wireless.wlan1.band
        r.routeros_interface_wireless.wlan2.band
        r.routeros_interface_wireless.wlan1.country
        r.routeros_interface_wireless.wlan1.security_profile
        r.routeros_interface_wireless_security_profiles.home.wpa2_pre_shared_key
        (r ? routeros_wifi)
      ];
      expected = [
        "ap-bridge"
        "TEST"
        "2ghz-b/g/n"
        "5ghz-a/n/ac"
        "Latvia"
        "\${routeros_interface_wireless_security_profiles.home.name}"
        "\${var.wifi_home}"
        false
      ];
    };
  testWifiPortsBridged = {
    expr =
      builtins.mapAttrs (_: p: p.interface)
        (render [
          base
          wifiHome
        ]).resource.routeros_interface_bridge_port;
    expected = {
      ether1 = "ether1";
      ether2 = "ether2";
      ether3 = "ether3";
      ether4 = "ether4";
      ether5 = "ether5";
      wifi1 = "\${routeros_wifi.wifi1.name}";
      wifi2 = "\${routeros_wifi.wifi2.name}";
    };
  };
  testWifiNoCountryFails = {
    expr = fails [
      base
      wifiHome
      { routeros.wifi.country = lib.mkForce null; }
    ];
    expected = true;
  };
  testWifiNoRadioFails = {
    expr = fails [
      base
      wifiHome
      {
        routeros.device = lib.mkForce {
          ethernet = [ "ether1" ];
          defaultUplink = "ether1";
        };
      }
    ];
    expected = true;
  };
  testWifiNetworkWithoutRadioFails = {
    expr = fails [
      base
      wifiHome
      {
        routeros.device = lib.mkForce (
          self.lib.devices.hap-ax3
          // {
            wifi.stack = "wifi";
            wifi.radios.wifi2.band = "2ghz";
          }
        );
        routeros.wifi.networks.home.bands = lib.mkForce [ "5ghz" ];
      }
    ];
    expected = true;
  };
  testWifiValidDoesNotFail = {
    expr = fails [
      base
      wifiHome
    ];
    expected = false;
  };
  testStationRadioApVirtual =
    let
      r =
        (render [
          base
          wifiHome
          (station false)
        ]).resource;
    in
    {
      expr = [
        r.routeros_wifi.wifi2.configuration.mode
        r.routeros_wifi.home_wifi2.master_interface
        r.routeros_wifi.wifi1.configuration.config
        (builtins.attrNames r.routeros_interface_bridge_port)
        (r.routeros_wifi.wifi2 ? lifecycle)
        r.routeros_ip_dhcp_client.hotspot.interface
      ];
      expected = [
        "station"
        "\${routeros_wifi.wifi2.name}"
        "\${routeros_wifi_configuration.home.name}"
        [
          "ether1"
          "ether2"
          "ether3"
          "ether4"
          "ether5"
          "home_wifi2"
          "wifi1"
        ]
        false
        "wifi2"
      ];
    };
  testStationIgnoreChanges = {
    expr = [
      (render [
        base
        (station true)
      ]).resource.routeros_wifi.wifi2.lifecycle.ignore_changes
      (render [
        base
        (station true)
        { routeros.device = lib.mkForce "hap-ac2"; }
        { routeros.uplinks.hotspot.station.radio = lib.mkForce "wlan1"; }
      ]).resource.routeros_interface_wireless.wlan1
    ];
    expected = [
      [
        "configuration"
        "security"
      ]
      {
        name = "wlan1";
        mode = "station";
        band = "2ghz-b/g/n";
        disabled = false;
        lifecycle.ignore_changes = [
          "ssid"
          "security_profile"
        ];
      }
    ];
  };
  testStationUnknownRadioFails = {
    expr = fails [
      base
      (station false)
      { routeros.uplinks.hotspot.station.radio = lib.mkForce "wlan9"; }
    ];
    expected = true;
  };
  testTwoStationsOneRadioFails = {
    expr = fails [
      base
      (station false)
      {
        routeros.uplinks.other = {
          kind = "wifi-station";
          station.radio = "wifi2";
          check.host = "9.9.9.8";
        };
      }
    ];
    expected = true;
  };
}
