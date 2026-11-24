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
        "${terranix}/core/terraform-options.nix"
        self.terranixModules.default
      ]
      ++ modules;
      specialArgs.pkgs = nixpkgs.legacyPackages.${system};
    }).config;
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
          routeros.network.subnet = "10.0.0.0/24";
        }
      ]).routeros._device.wifi.stack;
    expected = "wifi";
  };
  testDeviceAttrs = {
    expr =
      (evalConfig [
        {
          routeros.device = self.lib.devices.hap-ac2;
          routeros.network.subnet = "10.0.0.0/24";
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
  testRenderSmoke = {
    expr =
      (render [
        {
          routeros.network.subnet = "10.0.0.0/24";
          routeros.device = "hap-ax3";
        }
      ]) ? resource;
    expected = true;
  };
}
