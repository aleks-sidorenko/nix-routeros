{ config, lib, ... }:
let
  devices = import ../lib/devices.nix;
  customTypes = import ../lib/types.nix { inherit lib; };
in
{
  options.routeros = {
    device = lib.mkOption {
      type = lib.types.either (lib.types.enum (lib.attrNames devices)) customTypes.deviceType;
      description = "Router model: a built-in profile name, or a profile attrset for an unlisted model.";
      example = "hap-ax3";
    };

    _device = lib.mkOption {
      type = customTypes.deviceType;
      internal = true;
      readOnly = true;
      default =
        if lib.isString config.routeros.device then
          devices.${config.routeros.device}
        else
          config.routeros.device;
      description = "Resolved device profile.";
    };
  };
}
