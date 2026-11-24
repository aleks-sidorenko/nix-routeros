{ config, lib, ... }:
let
  cfg = config.routeros.dns;
  inherit (config.routeros._lib) sanitizeName escapeTemplate;

  recordType = lib.types.submodule (
    { name, ... }:
    {
      options =
        let
          optStr =
            description:
            lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              inherit description;
            };
        in
        {
          name = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "DNS name; defaults to the attribute name.";
          };
          type = lib.mkOption {
            type = lib.types.enum [
              "A"
              "AAAA"
              "CNAME"
              "FWD"
              "NXDOMAIN"
              "TXT"
            ];
            default = "A";
            description = "Record type. NXDOMAIN answers the name as nonexistent and carries no value.";
          };
          address = optStr "Address of an A or AAAA record.";
          cname = optStr "Target of a CNAME record.";
          forwardTo = optStr "DNS server an FWD record forwards to.";
          text = optStr "Content of a TXT record.";
          matchSubdomain = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Also match subdomains of the name.";
          };
          comment = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Record comment.";
          };
        };
    }
  );

  # The option each type needs.
  required = {
    A = "address";
    AAAA = "address";
    CNAME = "cname";
    FWD = "forwardTo";
    TXT = "text";
  };

  mkRecord =
    r:
    {
      name = escapeTemplate r.name;
      inherit (r) type;
      match_subdomain = r.matchSubdomain;
    }
    // lib.optionalAttrs (r.comment != "") { inherit (r) comment; }
    // lib.optionalAttrs (r.address != null) { address = escapeTemplate r.address; }
    // lib.optionalAttrs (r.cname != null) { cname = escapeTemplate r.cname; }
    // lib.optionalAttrs (r.forwardTo != null) { forward_to = escapeTemplate r.forwardTo; }
    // lib.optionalAttrs (r.text != null) { text = escapeTemplate r.text; };

in
{
  options.routeros.dns = {
    upstream = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Upstream DNS servers; at least one.";
      example = [ "1.1.1.1" ];
    };

    localDomain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "When set, each static lease is also resolvable as `<lease>.<localDomain>`.";
    };

    records = lib.mkOption {
      type = lib.types.attrsOf recordType;
      default = { };
      description = "Static DNS records by name.";
    };
  };

  config = {
    routeros._keys =
      lib.mapAttrsToList (key: _: {
        resource = "routeros_ip_dns_record";
        key = sanitizeName key;
        source = "routeros.dns.records.${key}";
      }) cfg.records
      ++ lib.optionals (cfg.localDomain != null) (
        lib.mapAttrsToList (name: _: {
          resource = "routeros_ip_dns_record";
          key = "lease_${sanitizeName name}";
          source = "routeros.lan.leases.${name}";
        }) config.routeros.lan.leases
      );

    routeros._checks = [
      {
        assertion = cfg.upstream != [ ];
        message = "routeros.dns.upstream must list at least one server";
      }
    ]
    ++ lib.concatLists (
      lib.mapAttrsToList (
        key: r:
        lib.optional (required ? ${r.type}) {
          assertion = r.${required.${r.type}} != null;
          message = "routeros.dns.records.${key}: type ${r.type} needs ${required.${r.type}}";
        }
      ) cfg.records
    );

    resource = {
      routeros_dns.settings = {
        allow_remote_requests = true;
        servers = cfg.upstream;
      };

      routeros_ip_dns_record =
        lib.mapAttrs' (key: r: lib.nameValuePair (sanitizeName key) (mkRecord r)) cfg.records
        // lib.optionalAttrs (cfg.localDomain != null) (
          lib.mapAttrs' (
            name: lease:
            lib.nameValuePair "lease_${sanitizeName name}" {
              name = escapeTemplate "${name}.${cfg.localDomain}";
              inherit (lease) address;
              type = "A";
            }
          ) config.routeros.lan.leases
        );
    };
  };
}
