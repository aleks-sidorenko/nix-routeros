# wifi-qcom (`/interface/wifi`). Interfaces reference named profiles through
# the `config` key of their inline maps, as in the provider's examples.
{
  lib,
  cfg,
  aps,
  stations,
  sanitizeName,
  escapeTemplate,
  ...
}:
let
  ref = type: key: "\${${type}.${key}.name}";
  netKeys = lib.mapAttrs' (net: n: lib.nameValuePair (sanitizeName net) (n // { name = net; }));
in
{
  interface = "routeros_wifi";
  # Keyed by network name.
  networkResource = "routeros_wifi_configuration";

  resource = {
    routeros_wifi_security = lib.mapAttrs (_: n: {
      inherit (n) name;
      authentication_types = [
        "wpa2-psk"
        "wpa3-psk"
      ];
      passphrase = "\${var.${n.passphraseVariable}}";
    }) (netKeys cfg.networks);

    routeros_wifi_configuration = lib.mapAttrs (key: n: {
      inherit (n) name;
      ssid = escapeTemplate n.ssid;
      inherit (cfg) country;
      mode = "ap";
      security.config = ref "routeros_wifi_security" key;
    }) (netKeys cfg.networks);

    routeros_wifi =
      lib.listToAttrs (
        map (
          ap:
          lib.nameValuePair ap.key (
            {
              inherit (ap) name;
              configuration.config = ref "routeros_wifi_configuration" (sanitizeName ap.net);
              disabled = false;
            }
            // lib.optionalAttrs (!ap.master) { master_interface = ref "routeros_wifi" ap.masterKey; }
          )
        ) aps
      )
      // lib.mapAttrs' (
        radio: u:
        lib.nameValuePair (sanitizeName radio) (
          {
            name = radio;
            configuration = {
              mode = "station";
            }
            // lib.optionalAttrs (cfg.country != null) { inherit (cfg) country; };
            disabled = false;
          }
          // lib.optionalAttrs u.runtimeManaged {
            lifecycle.ignore_changes = [
              "configuration"
              "security"
            ];
          }
        )
      ) stations;
  };
}
