{ config, lib, ... }:
let
  helpers = import ../lib/helpers.nix { inherit lib; };
  failed = lib.filter (c: !c.assertion) config.routeros._checks;
in
{
  imports = [
    ./device.nix
    ./connection.nix
    ./system.nix
    ./lan.nix
    ./uplinks.nix
    ./dns.nix
    ./firewall.nix
    ./wifi
  ];

  options.routeros = {
    # terranix has no `assertions`; modules append here and the entries are
    # forced through `resource`, so a failed one aborts evaluation.
    _checks = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            assertion = lib.mkOption { type = lib.types.bool; };
            message = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      internal = true;
      default = [ ];
      description = "Evaluation-time checks: each fails evaluation with its message when its assertion is false.";
    };

    _lib = lib.mkOption {
      type = lib.types.attrs;
      internal = true;
      default = helpers;
    };
  };

  config.resource =
    if failed == [ ] then
      { }
    else
      throw "nix-routeros:\n${lib.concatMapStringsSep "\n" (c: "- ${c.message}") failed}";
}
