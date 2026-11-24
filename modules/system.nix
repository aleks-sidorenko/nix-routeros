{ config, lib, ... }:
let
  cfg = config.routeros.system;
  lanSubnet = config.routeros.lan.subnet;
  lanList = "\${routeros_interface_list.LAN.name}";
  # An interface list that is still empty would cut off MAC access.
  afterLan = {
    depends_on = [ "routeros_interface_list_member.bridge_LAN" ];
  };

  mkServiceOpt = name: defaults: {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = defaults.enable or true;
      description = "Whether to enable the ${name} service.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = defaults.port;
      description = "Port for the ${name} service.";
    };
    allowedAddresses = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = defaults.allowedAddresses or null;
      description = "Restrict ${name} to this address/subnet. null means unrestricted.";
    };
  };
in
{
  options.routeros.system = {
    identity = lib.mkOption {
      type = lib.types.str;
      default = "Router";
      description = "Router system identity (hostname).";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "UTC";
      description = "System timezone.";
    };

    services = {
      ssh = mkServiceOpt "SSH" {
        port = 22;
        allowedAddresses = lanSubnet;
      };
      winbox = mkServiceOpt "Winbox" {
        port = 8291;
        allowedAddresses = lanSubnet;
      };
      api = mkServiceOpt "API" {
        port = 8728;
        allowedAddresses = lanSubnet;
      };
      ftp = mkServiceOpt "FTP" {
        enable = false;
        port = 21;
      };
      telnet = mkServiceOpt "Telnet" {
        enable = false;
        port = 23;
      };
      www = mkServiceOpt "WWW" {
        enable = false;
        port = 80;
      };
      api-ssl = mkServiceOpt "API-SSL" {
        enable = false;
        port = 8729;
      };
    };

    ipSettings = {
      maxNeighborEntries = lib.mkOption {
        type = lib.types.int;
        default = 8192;
        description = "Maximum number of neighbor entries.";
      };
    };

    ipv6 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to enable IPv6.";
      };
      acceptRouterAdvertisements = lib.mkOption {
        type = lib.types.str;
        default = "yes";
        description = "Accept router advertisements (yes/no/yes-if-forwarding-disabled).";
      };
      maxNeighborEntries = lib.mkOption {
        type = lib.types.int;
        default = 8192;
        description = "Maximum IPv6 neighbor entries.";
      };
    };

    macServer = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable MAC server and MAC server winbox.";
      };
      allowedInterfaceList = lib.mkOption {
        type = lib.types.str;
        default = lanList;
        defaultText = "the LAN interface list";
        description = "Interface list allowed for MAC server access.";
      };
    };

    neighborDiscovery = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable neighbor discovery.";
      };
      interfaceList = lib.mkOption {
        type = lib.types.str;
        default = lanList;
        defaultText = "the LAN interface list";
        description = "Interface list for neighbor discovery.";
      };
    };
  };

  config = {
    resource = {
      routeros_system_identity.router = {
        name = cfg.identity;
      };

      routeros_system_clock.default = {
        time_zone_name = cfg.timezone;
        time_zone_autodetect = false;
      };

      routeros_ip_service =
        let
          mkSvc =
            numbers: svcCfg:
            {
              inherit numbers;
              inherit (svcCfg) port;
              disabled = !svcCfg.enable;
            }
            // lib.optionalAttrs (svcCfg.enable && svcCfg.allowedAddresses != null) {
              address = svcCfg.allowedAddresses;
            };
        in
        {
          ftp = mkSvc "ftp" cfg.services.ftp;
          ssh = mkSvc "ssh" cfg.services.ssh;
          telnet = mkSvc "telnet" cfg.services.telnet;
          www = mkSvc "www" cfg.services.www;
          winbox = mkSvc "winbox" cfg.services.winbox;
          api = mkSvc "api" cfg.services.api;
          api_ssl = mkSvc "api-ssl" cfg.services.api-ssl;
        };

      routeros_ip_neighbor_discovery_settings.default = afterLan // {
        discover_interface_list = cfg.neighborDiscovery.interfaceList;
      };

      routeros_ip_settings.default = {
        max_neighbor_entries = cfg.ipSettings.maxNeighborEntries;
      };

      routeros_ipv6_settings.default = {
        accept_router_advertisements = cfg.ipv6.acceptRouterAdvertisements;
        disable_ipv6 = !cfg.ipv6.enable;
        max_neighbor_entries = cfg.ipv6.maxNeighborEntries;
      };

      routeros_tool_mac_server.default = afterLan // {
        allowed_interface_list = cfg.macServer.allowedInterfaceList;
      };

      routeros_tool_mac_server_winbox.default = afterLan // {
        allowed_interface_list = cfg.macServer.allowedInterfaceList;
      };
    };
  };
}
