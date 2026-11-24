{ config, lib, ... }:
let
  cfg = config.routeros.interfaces;
  lteCfg = cfg.lte;
in
{
  options.routeros.interfaces = {
    wan = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "ether1" ];
      description = "WAN interfaces.";
    };

    lte = {
      enable = lib.mkEnableOption "LTE interface";

      apn = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "APN for LTE connection.";
      };

      provider = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "LTE provider name.";
      };
    };

    lists = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      description = "Additional interface list memberships beyond auto-generated WAN/LAN.";
    };
  };

  config = {
    resource = {
      # WAN ethernet interfaces
      routeros_interface_ethernet = builtins.listToAttrs (
        builtins.map (iface: {
          name = iface;
          value = {
            name = iface;
            factory_name = iface;
            comment = "WAN";
          };
        }) cfg.wan
      );

      # Interface lists
      routeros_interface_list = {
        WAN = {
          name = "WAN";
          comment = "defconf";
        };
      };

      # List members: WAN interfaces->WAN, LTE->WAN (if enabled)
      routeros_interface_list_member =
        builtins.listToAttrs (
          builtins.map (iface: {
            name = "${iface}_WAN";
            value = {
              interface = iface;
              list = "WAN";
              comment = "defconf";
            };
          }) cfg.wan
        )
        // lib.optionalAttrs lteCfg.enable {
          lte1_WAN = {
            interface = "lte1";
            list = "WAN";
          };
        };

      # LTE APN
      routeros_interface_lte_apn = lib.mkIf lteCfg.enable {
        default = {
          apn = lteCfg.apn;
          ip_type = "ipv4";
          ipv6_interface = "bridge";
          name = lteCfg.provider;
          use_network_apn = false;
        };
      };
    };
  };
}
