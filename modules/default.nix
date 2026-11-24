{ config, lib, ... }:
let
  helpers = import ../lib/helpers.nix { inherit lib; };
  failed = lib.filter (c: !c.assertion) (config.routeros._checks ++ variableChecks);
  # Duplicate names would silently merge into one Terraform variable.
  variableChecks = lib.mapAttrsToList (name: vs: {
    assertion = lib.length vs == 1;
    message = "Terraform variable ${name} is declared by more than one of: ${
      lib.concatMapStringsSep ", " (v: v.by) vs
    }";
  }) (builtins.groupBy (v: v.name) config.routeros._variables);
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

    _variables = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            by = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      internal = true;
      default = [ ];
      description = "Terraform variables the modules declare, with the option declaring each; names must be unique.";
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
