{ config, lib, ... }:
let
  cfg = config.routeros.wifi;
  device = config.routeros._device;
  inherit (config.routeros._lib) sanitizeName escapeTemplate;

  radios = if device.wifi == null then { } else device.wifi.radios;

  # A station must be its radio's master interface and the access points on
  # that radio virtual ones, which follow the station's upstream channel:
  #   https://manual.mikrotik.com/docs/wireless/wifi/configuring-repeater/
  #   https://help.mikrotik.com/docs/spaces/ROS/pages/8978446/Wireless+Interface
  #   ("master-interface ... only for virtual AP interfaces")
  stations = lib.listToAttrs (
    lib.mapAttrsToList (_: u: lib.nameValuePair u.station.radio u) (
      lib.filterAttrs (
        _: u: u.kind == "wifi-station" && radios ? ${toString u.station.radio}
      ) config.routeros.uplinks
    )
  );

  networksOn =
    band:
    let
      names = lib.attrNames (lib.filterAttrs (_: n: lib.elem band n.bands) cfg.networks);
      primary = lib.filter (n: cfg.networks.${n}.primary) names;
    in
    primary ++ lib.subtractLists primary names;

  # Per radio, the primary network (else the first by name) takes the radio
  # itself unless a station holds it; every other network is a virtual
  # interface on it.
  aps = lib.concatLists (
    lib.mapAttrsToList (
      radio: r:
      lib.imap0 (
        i: net:
        let
          master = i == 0 && !(stations ? ${radio});
        in
        {
          inherit radio net master;
          network = cfg.networks.${net};
          key = sanitizeName (if master then radio else "${net}_${radio}");
          name = if master then radio else "${net}-${radio}";
          masterKey = sanitizeName radio;
        }
      ) (networksOn r.band)
    ) radios
  );

  stack = import (if device.wifi.stack == "wifi" then ./wifi.nix else ./wireless.nix) {
    inherit
      lib
      cfg
      aps
      stations
      radios
      sanitizeName
      escapeTemplate
      ;
  };
in
{
  options.routeros.wifi = {
    country = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Regulatory country, in the form RouterOS expects; required when any network is set.";
      example = "Latvia";
    };

    networks = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            ssid = lib.mkOption {
              type = lib.types.str;
              description = "Network name.";
            };
            bands = lib.mkOption {
              type = lib.types.listOf (
                lib.types.enum [
                  "2ghz"
                  "5ghz"
                ]
              );
              default = [
                "2ghz"
                "5ghz"
              ];
              description = "Bands the network is offered on: every radio of a listed band carries it.";
            };
            primary = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Owns the radio interfaces on its bands; the other networks become
                virtual interfaces. At most one network is primary. With none, the
                first network by name owns them, which moves (and briefly drops
                clients) when a network sorting earlier is added.
              '';
            };
            passphraseVariable = lib.mkOption {
              type = lib.types.str;
              description = "Name of the sensitive Terraform variable holding the passphrase.";
              example = "wifi_home";
            };
          };
        }
      );
      default = { };
      description = "Access point networks by name; the primary one (else the first by name) takes each radio, the rest become virtual interfaces.";
    };
  };

  config = {
    routeros = {
      _checks =
        lib.optionals (cfg.networks != { }) [
          {
            assertion = cfg.country != null;
            message = "routeros.wifi.country must be set when routeros.wifi.networks is not empty";
          }
          {
            assertion = device.wifi != null;
            message = "routeros.wifi.networks is set but the device profile has no Wi-Fi (wifi = null)";
          }
        ]
        ++ [
          {
            assertion = lib.length (lib.attrNames (lib.filterAttrs (_: n: n.primary) cfg.networks)) <= 1;
            message = "routeros.wifi.networks: at most one network may be primary";
          }
        ]
        ++ lib.optionals (device.wifi != null) (
          lib.mapAttrsToList (name: n: {
            assertion = lib.any (r: lib.elem r.band n.bands) (lib.attrValues radios);
            message = "routeros.wifi.networks.${name}: no radio of the device serves bands ${lib.concatStringsSep ", " n.bands}";
          }) cfg.networks
        );
      _keys = lib.optionals (device.wifi != null) (
        lib.mapAttrsToList (name: _: {
          resource = stack.networkResource;
          key = sanitizeName name;
          source = "routeros.wifi.networks.${name}";
        }) cfg.networks
      );
      _variables = lib.mapAttrsToList (name: n: {
        name = n.passphraseVariable;
        by = "routeros.wifi.networks.${name}.passphraseVariable";
      }) cfg.networks;
      _wifiPorts = lib.optionalAttrs (device.wifi != null) (
        lib.listToAttrs (map (ap: lib.nameValuePair ap.key "\${${stack.interface}.${ap.key}.name}") aps)
      );
    };

    variable = lib.mapAttrs' (
      _: n:
      lib.nameValuePair n.passphraseVariable {
        type = "string";
        sensitive = true;
        description = "Wi-Fi network passphrase";
      }
    ) cfg.networks;

    resource = lib.optionalAttrs (device.wifi != null) stack.resource;
  };
}
