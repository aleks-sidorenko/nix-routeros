{ config, lib, ... }:
let
  cfg = config.routeros.system;
  lanSubnet = config.routeros.lan.subnet;

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
        default = "LAN";
        description = "Interface list allowed for MAC server access.";
      };
    };

    ipsec = {
      dpdInterval = lib.mkOption {
        type = lib.types.str;
        default = "2m";
        description = "Dead Peer Detection interval.";
      };
      dpdMaxFailures = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Maximum DPD failures before peer is considered dead.";
      };
    };

    bfd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable BFD (Bidirectional Forwarding Detection).";
    };

    neighborDiscovery = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable neighbor discovery.";
      };
      interfaceList = lib.mkOption {
        type = lib.types.str;
        default = "LAN";
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
            name: numbers: svcCfg:
            {
              inherit numbers;
              port = svcCfg.port;
              disabled = !svcCfg.enable;
            }
            // lib.optionalAttrs (svcCfg.enable && svcCfg.allowedAddresses != null) {
              address = svcCfg.allowedAddresses;
            };
        in
        {
          ftp = mkSvc "ftp" "ftp" cfg.services.ftp;
          ssh = mkSvc "ssh" "ssh" cfg.services.ssh;
          telnet = mkSvc "telnet" "telnet" cfg.services.telnet;
          www = mkSvc "www" "www" cfg.services.www;
          winbox = mkSvc "winbox" "winbox" cfg.services.winbox;
          api = mkSvc "api" "api" cfg.services.api;
          api_ssl = mkSvc "api-ssl" "api-ssl" cfg.services.api-ssl;
        };

      routeros_ip_neighbor_discovery_settings.default = {
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

      routeros_ip_ipsec_profile.default = {
        name = "default";
        dpd_interval = cfg.ipsec.dpdInterval;
        dpd_maximum_failures = cfg.ipsec.dpdMaxFailures;
      };

      routeros_routing_bfd_configuration.default = {
        disabled = !cfg.bfd.enable;
      };

      routeros_tool_mac_server.default = {
        allowed_interface_list = cfg.macServer.allowedInterfaceList;
      };

      routeros_tool_mac_server_winbox.default = {
        allowed_interface_list = cfg.macServer.allowedInterfaceList;
      };
    };
  };
}
