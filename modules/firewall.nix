{ config, lib, ... }:
let
  cfg = config.routeros.firewall;
  helpers = config.routeros._lib;
  inherit (helpers) sanitizeName;
  wan = "\${routeros_interface_list.WAN.name}";

  # Generic home router rules only; site-specific ones go in filterRules.
  presetFilterRules = lib.optionals cfg.defaults [
    {
      name = "input_accept_established";
      action = "accept";
      chain = "input";
      comment = "defconf: accept established,related,untracked";
      connection_state = "established,related,untracked";
    }
    {
      name = "input_drop_invalid";
      action = "drop";
      chain = "input";
      comment = "defconf: drop invalid";
      connection_state = "invalid";
    }
    {
      name = "input_accept_icmp";
      action = "accept";
      chain = "input";
      comment = "defconf: accept ICMP";
      protocol = "icmp";
    }
    {
      name = "input_drop_non_lan";
      action = "drop";
      chain = "input";
      comment = "defconf: drop all not coming from LAN";
      in_interface_list = "!\${routeros_interface_list.LAN.name}";
      # place_before creates the chain from its end, so without this the
      # drop could land while LAN is still empty and lock the session out.
      depends_on = [ "routeros_interface_list_member.bridge_LAN" ];
    }
    {
      name = "forward_accept_ipsec_in";
      action = "accept";
      chain = "forward";
      comment = "defconf: accept in ipsec policy";
      ipsec_policy = "in,ipsec";
    }
    {
      name = "forward_accept_ipsec_out";
      action = "accept";
      chain = "forward";
      comment = "defconf: accept out ipsec policy";
      ipsec_policy = "out,ipsec";
    }
    {
      name = "forward_fasttrack";
      action = "fasttrack-connection";
      chain = "forward";
      comment = "defconf: fasttrack";
      connection_state = "established,related";
    }
    {
      name = "forward_accept_established";
      action = "accept";
      chain = "forward";
      comment = "defconf: accept established,related, untracked";
      connection_state = "established,related,untracked";
    }
    {
      name = "forward_drop_invalid";
      action = "drop";
      chain = "forward";
      comment = "defconf: drop invalid";
      connection_state = "invalid";
    }
    {
      name = "forward_drop_wan_not_dstnat";
      action = "drop";
      chain = "forward";
      comment = "defconf: drop all from WAN not DSTNATed";
      connection_nat_state = "!dstnat";
      connection_state = "new";
      in_interface_list = wan;
    }
  ];

  # Preset default NAT rules
  presetNatRules = lib.optionals cfg.defaults [
    {
      name = "masquerade";
      action = "masquerade";
      chain = "srcnat";
      comment = "defconf: masquerade";
      ipsec_policy = "out,none";
      out_interface_list = wan;
    }
    {
      name = "dns_redirect";
      action = "redirect";
      chain = "dstnat";
      dst_port = 53;
      protocol = "udp";
      to_addresses = (helpers.parseCidr config.routeros.lan.address).address;
      to_ports = 53;
    }
  ];

  # Combined rules: preset + user
  allFilterRules = presetFilterRules ++ cfg.filterRules;
  allNatRules = presetNatRules ++ cfg.natRules;

  # Build filter rule resources with place_before chaining
  filterRuleCount = builtins.length allFilterRules;
  mkFilterRule =
    idx:
    let
      rule = builtins.elemAt allFilterRules idx;
      ruleAttrs = builtins.removeAttrs rule [ "name" ];
      withOrdering =
        if idx < filterRuleCount - 1 then
          let
            nextRule = builtins.elemAt allFilterRules (idx + 1);
          in
          ruleAttrs // { place_before = "\${routeros_ip_firewall_filter.${sanitizeName nextRule.name}.id}"; }
        else
          ruleAttrs;
    in
    {
      name = sanitizeName rule.name;
      value = withOrdering;
    };

  # Build NAT rule resources (no place_before — NAT ordering is less critical
  # and place_before forces destructive replacement on existing routers)
  mkNatRule =
    idx:
    let
      rule = builtins.elemAt allNatRules idx;
    in
    {
      name = sanitizeName rule.name;
      value = builtins.removeAttrs rule [ "name" ];
    };

  ruleKeys =
    resource: option: rules:
    map (r: {
      inherit resource;
      key = sanitizeName r.name;
      source = "routeros.firewall.${option} rule ${r.name}";
    }) rules;

  addressEntries = lib.concatLists (
    lib.mapAttrsToList (
      list:
      map (address: {
        inherit list address;
        key = sanitizeName (builtins.replaceStrings [ "/" ":" ] [ "_" "_" ] "${list}_${address}");
      })
    ) cfg.addressLists
  );
in
{
  options.routeros.firewall = {
    defaults = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Include the preset defconf filter and NAT rules (including the DNS
        redirect to the router); false leaves only the rules you list. The
        router always answers DNS queries, so with false it is an open
        resolver on the WAN unless your rules drop input from it.
      '';
    };

    connectionTracking = {
      udpTimeout = lib.mkOption {
        type = lib.types.str;
        default = "10s";
        description = "UDP connection tracking timeout.";
      };
    };

    addressLists = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      description = "Firewall address lists. Keys are list names, values are lists of addresses.";
      example = {
        tv = [
          "10.0.0.50"
          "10.0.0.51"
        ];
      };
    };

    filterRules = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [ ];
      description = "Additional firewall filter rules appended after preset rules. Each rule must have a unique 'name' attribute.";
    };

    natRules = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [ ];
      description = "Additional NAT rules appended after preset rules. Each rule must have a unique 'name' attribute.";
    };
  };

  config = {
    routeros._keys =
      ruleKeys "routeros_ip_firewall_filter" "defaults" presetFilterRules
      ++ ruleKeys "routeros_ip_firewall_filter" "filterRules" cfg.filterRules
      ++ ruleKeys "routeros_ip_firewall_nat" "defaults" presetNatRules
      ++ ruleKeys "routeros_ip_firewall_nat" "natRules" cfg.natRules
      ++ map (e: {
        resource = "routeros_ip_firewall_addr_list";
        inherit (e) key;
        source = "routeros.firewall.addressLists.${e.list} ${e.address}";
      }) addressEntries;

    resource = {
      routeros_ip_firewall_connection_tracking.default = {
        udp_timeout = cfg.connectionTracking.udpTimeout;
      };

      routeros_ip_firewall_addr_list = builtins.listToAttrs (
        map (e: lib.nameValuePair e.key { inherit (e) address list; }) addressEntries
      );

      routeros_ip_firewall_filter = builtins.listToAttrs (builtins.genList mkFilterRule filterRuleCount);

      routeros_ip_firewall_nat = builtins.listToAttrs (
        builtins.genList mkNatRule (builtins.length allNatRules)
      );
    };
  };
}
