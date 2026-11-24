{ config, lib, ... }:
let
  cfg = config.routeros.uplinks;
  device = config.routeros._device;
  helpers = config.routeros._lib;
  customTypes = import ../lib/types.nix { inherit lib; };
  inherit (helpers) sanitizeName;

  dhcpKinds = [
    "ethernet"
    "wifi-station"
  ];
  isDhcp = u: lib.elem u.kind dhcpKinds;
  tag = name: "nix-routeros:${sanitizeName name}";

  # Keeps the check host reachable only through this uplink so the default
  # route's `check_gateway` tests the uplink itself. The route is made on the
  # router when the lease binds, so it is never in Terraform state and is not
  # drift.
  dhcpScript = name: u: ''
    :local dst "${u.check.host}/32"; :local tag "${tag name}"
    :if ($bound = 1) do={
      :local gw $"gateway-address"
      :local r [/ip route find where comment=$tag]
      :if ([:len $r] = 0) do={ /ip route add dst-address=$dst gateway=$gw scope=10 comment=$tag } else={ /ip route set $r gateway=$gw }
    } else={ /ip route remove [/ip route find where comment=$tag] }
  '';

  mapUplinks = f: lib.mapAttrs' (name: u: lib.nameValuePair (sanitizeName name) (f name u));
  only = pred: lib.filterAttrs (_: pred);
  byHost = builtins.groupBy (u: u.check.host) named;
  ltes = only (u: u.kind == "lte") cfg;
  stationsByRadio = builtins.groupBy (u: toString u.station.radio) (
    lib.mapAttrsToList (name: u: u // { inherit name; }) (only (u: u.kind == "wifi-station") cfg)
  );
  pppoes = only (u: u.kind == "pppoe") cfg;

  # Interfaces this configuration manages are referenced so OpenTofu
  # creates them before the routes and list members that use them.
  interfaceRef =
    name: u:
    {
      lte = "\${routeros_interface_lte.${sanitizeName name}.name}";
      pppoe = "\${routeros_interface_pppoe_client.${sanitizeName name}.name}";
    }
    .${u.kind} or u.interface;

  named = lib.mapAttrsToList (name: u: u // { inherit name; }) cfg;
  names = us: lib.concatMapStringsSep ", " (u: u.name) us;
  # PPPoE runs over the device's uplink port.
  portOf = u: if u.kind == "pppoe" then device.defaultUplink else u.interface;
  # Only a DHCP ethernet uplink and a PPPoE session over it can share a port.
  canShare =
    us:
    lib.length us <= 1
    ||
      lib.sort lib.lessThan (map (u: u.kind) us) == [
        "ethernet"
        "pppoe"
      ];
in
{
  options.routeros.uplinks = lib.mkOption {
    type = lib.types.attrsOf (customTypes.uplinkType { inherit (device) defaultUplink; });
    default = { };
    description = "Internet uplinks by name; the lowest `distance` that passes its check carries traffic.";
  };

  config = {
    routeros = {
      _uplinkInterfaces =
        lib.mapAttrsToList (_: u: u.interface) (only (u: u.kind == "ethernet") cfg)
        ++ lib.mapAttrsToList (_: _: device.defaultUplink) pppoes;
      _keys = lib.mapAttrsToList (name: _: {
        resource = "routeros_interface_list_member";
        key = sanitizeName name;
        source = "routeros.uplinks.${name}";
      }) cfg;
      _checks = lib.concatLists (
        lib.mapAttrsToList (distance: us: [
          {
            assertion = lib.length us == 1;
            message = "routeros.uplinks ${names us} share distance ${distance}; equal distances balance traffic across them (ECMP) instead of failing over, so give each a distinct distance";
          }
        ]) (builtins.groupBy (u: toString u.distance) named)
        ++ lib.mapAttrsToList (port: us: [
          {
            assertion = canShare us;
            message = "routeros.uplinks ${names us} share port ${port}; only an ethernet uplink and a PPPoE uplink may share one";
          }
        ]) (builtins.groupBy portOf named)
        ++ lib.mapAttrsToList (host: us: [
          {
            assertion = lib.length us == 1;
            message = "routeros.uplinks ${names us} share check.host ${host}; their /32 routes would collide";
          }
          {
            assertion = !(lib.elem host config.routeros.dns.upstream);
            message = "routeros.uplinks.${(lib.head us).name}.check.host ${host} is also a DNS upstream; its /32 route would pin DNS to one uplink";
          }
        ]) byHost
        ++ lib.mapAttrsToList (radio: us: [
          {
            assertion = lib.length us == 1;
            message = "routeros.uplinks ${names us} run a station on the same radio ${radio}";
          }
        ]) stationsByRadio
        ++ lib.mapAttrsToList (name: u: [
          {
            assertion = u.kind != "lte" || device.usb;
            message = "routeros.uplinks.${name}: kind lte needs a device with a USB port";
          }
          {
            assertion =
              u.kind != "wifi-station"
              || (u.station.radio != null && device.wifi != null && device.wifi.radios ? ${u.station.radio});
            message = "routeros.uplinks.${name}: station.radio must name a radio of the device";
          }
          {
            assertion = u.kind != "wifi-station" || u.runtimeManaged;
            message = "routeros.uplinks.${name}: a wifi-station's SSID and credentials are chosen on the router at runtime, so runtimeManaged must be true";
          }
          {
            assertion = u.kind != "wifi-station" || u.interface == u.station.radio;
            message = "routeros.uplinks.${name}: a station runs on its radio's own interface, so interface must equal station.radio";
          }
          {
            assertion = u.kind != "pppoe" || (u.pppoe.user != null && u.pppoe.passwordVariable != null);
            message = "routeros.uplinks.${name}: kind pppoe needs pppoe.user and pppoe.passwordVariable";
          }
        ]) cfg
      );
      _variables = lib.mapAttrsToList (name: u: {
        name = u.pppoe.passwordVariable;
        by = "routeros.uplinks.${name}.pppoe.passwordVariable";
      }) (only (u: u.pppoe.passwordVariable != null) pppoes);
    };

    variable = lib.mkMerge (
      lib.mapAttrsToList (_: u: {
        ${u.pppoe.passwordVariable} = {
          type = "string";
          sensitive = true;
          description = "PPPoE password";
        };
      }) (only (u: u.pppoe.passwordVariable != null) pppoes)
    );

    resource = {
      routeros_interface_list.WAN = {
        name = "WAN";
        comment = "defconf";
      };

      routeros_interface_list_member = mapUplinks (name: u: {
        interface = interfaceRef name u;
        list = "\${routeros_interface_list.WAN.name}";
      }) cfg;

      routeros_ip_dhcp_client = mapUplinks (name: u: {
        inherit (u) interface;
        add_default_route = "no";
        use_peer_dns = false;
        script = dhcpScript name u;
        comment = name;
      }) (only isDhcp cfg);

      routeros_ip_route =
        lib.mapAttrs' (
          name: u:
          lib.nameValuePair "${sanitizeName name}_default" {
            dst_address = "0.0.0.0/0";
            gateway = u.check.host;
            inherit (u) distance;
            check_gateway = "ping";
            target_scope = 11;
            comment = name;
          }
        ) cfg
        // lib.mapAttrs' (
          name: u:
          lib.nameValuePair "${sanitizeName name}_check" {
            dst_address = "${u.check.host}/32";
            gateway = interfaceRef name u;
            scope = 10;
            comment = name;
          }
        ) (only (u: !isDhcp u) cfg);

      # The LTE interface is built in, so it is only attached to our profile;
      # a profile that added its own default route would bypass check_gateway.
      routeros_interface_lte_apn = mapUplinks (
        name: u:
        {
          inherit name;
          add_default_route = false;
          use_peer_dns = false;
          use_network_apn = u.lte.apn == null;
        }
        // lib.optionalAttrs (u.lte.apn != null) { inherit (u.lte) apn; }
      ) ltes;

      routeros_interface_lte = mapUplinks (name: u: {
        name = u.interface;
        apn_profiles = "\${routeros_interface_lte_apn.${sanitizeName name}.name}";
      }) ltes;

      routeros_interface_pppoe_client = mapUplinks (name: u: {
        name = u.interface;
        interface = device.defaultUplink;
        inherit (u.pppoe) user;
        password = "\${var.${toString u.pppoe.passwordVariable}}";
        add_default_route = false;
        use_peer_dns = false;
        comment = name;
      }) pppoes;
    };
  };
}
