{ lib, ... }:
let
  helpers = import ../lib/helpers.nix { inherit lib; };
  customTypes = import ../lib/types.nix { inherit lib; };
in
{
  imports = [
    ./device.nix
    ./connection.nix
    ./system.nix
    ./bridge.nix
    ./interfaces.nix
    ./dhcp.nix
    ./dns.nix
    ./firewall.nix
    ./wifi.nix
  ];

  options.routeros = {
    hosts = lib.mkOption {
      type = lib.types.attrsOf customTypes.hostType;
      default = { };
      description = "Host inventory. Drives DHCP leases, DNS records, and aliases.";
    };

    # Shared network option consumed by system.nix and dhcp.nix
    network.subnet = lib.mkOption {
      type = lib.types.str;
      description = "Network subnet in CIDR notation (e.g. 10.0.0.0/24).";
    };

    # Internal: expose helpers to other modules
    _lib = lib.mkOption {
      type = lib.types.attrs;
      internal = true;
      default = helpers;
    };
  };
}
