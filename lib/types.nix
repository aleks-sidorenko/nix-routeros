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

  leaseType = types.submodule {
    options = {
      mac = mkOption {
        type = types.str;
        description = "MAC address of the host.";
      };
      address = mkOption {
        type = types.str;
        description = "Fixed IP address; must be inside the LAN subnet and outside the DHCP pool.";
      };
      comment = mkOption {
        type = types.str;
        default = "";
        description = "Lease comment; defaults to the lease name.";
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
