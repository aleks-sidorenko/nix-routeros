{ lib }:
let
  inherit (lib) mkOption types;
in
{
  deviceType = types.submodule {
    options = {
      ethernet = mkOption {
        type = types.listOf types.str;
        description = "Ethernet port names.";
      };
      defaultUplink = mkOption {
        type = types.str;
        description = "Port used as the uplink unless configured otherwise.";
      };
      wifi = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              stack = mkOption {
                type = types.enum [
                  "wifi"
                  "wireless"
                ];
                description = "RouterOS Wi-Fi package (wifi = wifi-qcom, wireless = legacy).";
              };
              radios = mkOption {
                type = types.attrsOf (
                  types.submodule {
                    options.band = mkOption {
                      type = types.enum [
                        "2ghz"
                        "5ghz"
                      ];
                      description = "Radio band.";
                    };
                  }
                );
                description = "Radio interfaces by name.";
              };
            };
          }
        );
        default = null;
        description = "Wi-Fi hardware, or null when the device has none.";
      };
      usb = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the device has a USB port.";
      };
    };
  };

  hostType = types.submodule {
    options = {
      ip = mkOption {
        type = types.str;
        description = "IP address of the host.";
      };
      mac = mkOption {
        type = types.str;
        description = "MAC address of the host.";
      };
      comment = mkOption {
        type = types.str;
        default = "";
        description = "Comment for DHCP lease and DNS record.";
      };
      dhcp = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to create a static DHCP lease.";
      };
      dns = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to create a DNS A record.";
      };
      aliases = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional DNS names pointing to this host's IP.";
      };
    };
  };

  firewallRuleType = types.submodule {
    freeformType = types.attrsOf types.anything;
    options = {
      name = mkOption {
        type = types.str;
        description = "Unique resource name for this rule.";
      };
      action = mkOption {
        type = types.str;
        description = "Firewall action (accept, drop, fasttrack-connection, etc.).";
      };
      chain = mkOption {
        type = types.str;
        description = "Firewall chain (input, forward, srcnat, dstnat).";
      };
    };
  };

  natRuleType = types.submodule {
    freeformType = types.attrsOf types.anything;
    options = {
      name = mkOption {
        type = types.str;
        description = "Unique resource name for this NAT rule.";
      };
      action = mkOption {
        type = types.str;
        description = "NAT action (masquerade, redirect, dst-nat, etc.).";
      };
      chain = mkOption {
        type = types.str;
        description = "NAT chain (srcnat, dstnat).";
      };
    };
  };
}
