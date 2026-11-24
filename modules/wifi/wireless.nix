# Legacy wireless (`/interface/wireless`).
{
  lib,
  cfg,
  aps,
  stations,
  radios,
  sanitizeName,
  ...
}:
let
  ref = type: key: "\${${type}.${key}.name}";
  netKeys = lib.mapAttrs' (net: n: lib.nameValuePair (sanitizeName net) (n // { name = net; }));
  bandModes = {
    "2ghz" = "2ghz-b/g/n";
    "5ghz" = "5ghz-a/n/ac";
  };
in
{
  interface = "routeros_interface_wireless";

  resource = {
    # The legacy package has no WPA3.
    routeros_interface_wireless_security_profiles = lib.mapAttrs (_: n: {
      inherit (n) name;
      mode = "dynamic-keys";
      authentication_types = [ "wpa2-psk" ];
      unicast_ciphers = "aes-ccm";
      group_ciphers = "aes-ccm";
      wpa2_pre_shared_key = "\${var.${n.passphraseVariable}}";
    }) (netKeys cfg.networks);

    routeros_interface_wireless =
      lib.listToAttrs (
        map (
          ap:
          lib.nameValuePair ap.key (
            {
              inherit (ap) name;
              inherit (ap.network) ssid;
              mode = "ap-bridge";
              security_profile = ref "routeros_interface_wireless_security_profiles" (sanitizeName ap.net);
              disabled = false;
            }
            // (
              if ap.master then
                {
                  inherit (cfg) country;
                  band = bandModes.${radios.${ap.radio}.band};
                }
              else
                { master_interface = ref "routeros_interface_wireless" ap.masterKey; }
            )
          )
        ) aps
      )
      // lib.mapAttrs' (
        radio: u:
        lib.nameValuePair (sanitizeName radio) (
          {
            name = radio;
            mode = "station";
            band = bandModes.${radios.${radio}.band};
            disabled = false;
          }
          // lib.optionalAttrs (cfg.country != null) { inherit (cfg) country; }
          // lib.optionalAttrs u.runtimeManaged {
            lifecycle.ignore_changes = [
              "ssid"
              "security_profile"
            ];
          }
        )
      ) stations;
  };
}
