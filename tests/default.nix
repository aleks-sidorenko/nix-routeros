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
}
