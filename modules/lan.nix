{ config, lib, ... }:
let
  cfg = config.routeros.lan;
  helpers = config.routeros._lib;
  customTypes = import ../lib/types.nix { inherit lib; };
  router = (helpers.parseCidr cfg.address).address;
  inherit (helpers) sanitizeName;
  leases = lib.mapAttrsToList (name: lease: lease // { inherit name; }) cfg.leases;
  # Reports each value held by more than one lease, naming all its leases.
  duplicates =
    what: key:
    lib.mapAttrsToList (value: ls: {
      assertion = lib.length ls == 1;
      message = "routeros.lan.leases ${
        lib.concatMapStringsSep ", " (l: l.name) ls
      } share ${what} ${value}";
    }) (builtins.groupBy key leases);
  leaseChecks =
    lib.concatMap (lease: [
      {
        assertion = helpers.ipInCidr lease.address cfg.subnet;
        message = "routeros.lan.leases.${lease.name}: ${lease.address} is outside the LAN subnet ${cfg.subnet}";
      }
      {
        assertion = cfg.dhcp.pool == null || !(helpers.ipInRange lease.address cfg.dhcp.pool);
        message = "routeros.lan.leases.${lease.name}: ${lease.address} is inside the DHCP pool ${toString cfg.dhcp.pool}";
      }
      {
        assertion = lease.address != router;
        message = "routeros.lan.leases.${lease.name}: ${lease.address} is the router's own address";
      }
    ]) leases
    ++ duplicates "MAC" (l: lib.toLower l.mac)
    ++ duplicates "address" (l: l.address);
in
{
  options.routeros = {
    lan = {
      address = lib.mkOption {
        type = lib.types.str;
        description = "Router address on the LAN, in CIDR notation.";
        example = "10.0.0.1/24";
      };

      subnet = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default =
          let
            c = helpers.parseCidr cfg.address;
          in
          "${c.network}/${toString c.prefix}";
        description = "LAN network derived from `address`.";
      };

      ports = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = lib.subtractLists config.routeros._uplinkInterfaces config.routeros._device.ethernet;
        defaultText = "device ethernet ports minus uplink interfaces";
        description = "Interfaces bridged into the LAN.";
      };

      dhcp = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Run a DHCP server on the LAN.";
        };
        pool = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Dynamic address range, required when DHCP is enabled.";
          example = "10.0.0.100-10.0.0.250";
        };
        leaseTime = lib.mkOption {
          type = lib.types.str;
          default = "1d";
          description = "DHCP lease duration.";
        };
      };

      leases = lib.mkOption {
        type = lib.types.attrsOf customTypes.leaseType;
        default = { };
        description = "Static DHCP leases by name.";
      };
    };

    # Set by the uplink module so LAN ports never include a WAN port.
    _uplinkInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      internal = true;
      default = [ ];
      description = "Interfaces used by uplinks.";
    };

    # Set by the Wi-Fi module, apart from `lan.ports` so overriding the
    # ports keeps the access points bridged.
    _wifiPorts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      internal = true;
      default = { };
      description = "Access point interfaces bridged into the LAN, by resource name.";
    };
  };

  config = {
    routeros._checks =
      lib.optional (cfg.dhcp.enable && cfg.dhcp.pool == null) {
        assertion = false;
        message = "routeros.lan.dhcp.pool must be set when the DHCP server is enabled";
      }
      ++ leaseChecks;

    resource = {
      routeros_interface_bridge.bridge = {
        name = "bridge";
        auto_mac = true;
        comment = "defconf";
        port_cost_mode = "short";
      };

      routeros_interface_bridge_port = lib.mapAttrs (_: interface: {
        bridge = "bridge";
        inherit interface;
        comment = "defconf";
        ingress_filtering = false;
        internal_path_cost = 10;
        path_cost = 10;
      }) (lib.genAttrs cfg.ports lib.id // config.routeros._wifiPorts);

      routeros_ip_address.lan = {
        address = cfg.address;
        interface = "bridge";
        network = (helpers.parseCidr cfg.address).network;
        comment = "defconf";
      };

      routeros_interface_list.LAN = {
        name = "LAN";
        comment = "defconf";
      };

      routeros_interface_list_member.bridge_LAN = {
        interface = "bridge";
        list = "LAN";
        comment = "defconf";
      };
    }
    // lib.optionalAttrs cfg.dhcp.enable {
      routeros_ip_pool.lan = {
        name = "lan";
        ranges = [ cfg.dhcp.pool ];
      };

      routeros_ip_dhcp_server.lan = {
        name = "lan";
        address_pool = "lan";
        interface = "bridge";
        lease_time = cfg.dhcp.leaseTime;
        dynamic_lease_identifiers = "client-mac,client-id";
      };

      routeros_ip_dhcp_server_network.lan = {
        address = cfg.subnet;
        gateway = router;
        dns_server = [ router ];
        netmask = toString (helpers.parseCidr cfg.address).prefix;
        comment = "defconf";
      };

      routeros_ip_dhcp_server_lease = lib.mapAttrs' (
        name: lease:
        lib.nameValuePair (sanitizeName name) {
          inherit (lease) address;
          mac_address = lib.toUpper lease.mac;
          comment = if lease.comment != "" then lease.comment else name;
          server = "lan";
        }
      ) cfg.leases;
    };
  };
}
