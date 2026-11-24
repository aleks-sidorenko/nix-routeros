{ lib }:
let
  inherit (lib) mkOption types;
in
{
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
