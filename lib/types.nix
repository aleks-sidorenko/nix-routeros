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

  # `defaultUplink` is the device's uplink port, the default interface of an ethernet uplink.
  uplinkType =
    { defaultUplink }:
    types.submodule (
      { name, config, ... }:
      {
        options = {
          kind = mkOption {
            type = types.enum [
              "ethernet"
              "wifi-station"
              "lte"
              "pppoe"
            ];
            description = "How the uplink connects.";
          };
          interface = mkOption {
            type = types.str;
            default =
              {
                ethernet = defaultUplink;
                lte = "lte1";
                pppoe = "pppoe-${name}";
                wifi-station = toString config.station.radio;
              }
              .${config.kind};
            defaultText = "by kind: the device uplink port, lte1, pppoe-<name>, station.radio";
            description = "Interface carrying the uplink.";
          };
          distance = mkOption {
            type = types.int;
            default = 1;
            description = "Default route distance; the lowest healthy uplink wins.";
          };
          check.host = mkOption {
            type = types.str;
            description = "Address pinged to decide whether the uplink is up; reached only through this uplink, so it must be unique and not a DNS upstream.";
            example = "1.0.0.1";
          };
          runtimeManaged = mkOption {
            type = types.bool;
            default = false;
            description = "The interface is configured on the router by hand (a Wi-Fi station whose network is joined at runtime), so Terraform ignores its connection settings.";
          };
          lte.apn = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "APN to configure; null leaves the router's APN settings alone.";
          };
          pppoe = {
            user = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "PPPoE username.";
            };
            passwordVariable = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Name of the sensitive Terraform variable holding the PPPoE password.";
            };
          };
          station.radio = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Radio that runs the station; its access points become virtual interfaces following the upstream channel.";
          };
        };
      }
    );

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
