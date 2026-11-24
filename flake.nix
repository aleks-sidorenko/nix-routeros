{
  description = "NixOS-module-style interface for configuring MikroTik RouterOS via terranix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    terranix = {
      url = "github:terranix/terranix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      terranix,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      helpers = import ./lib/helpers.nix { inherit lib; };

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems =
        f: builtins.listToAttrs (builtins.map (system: lib.nameValuePair system (f system)) systems);
    in
    {
      # Terranix modules — system-independent
      terranixModules = {
        default = ./modules;
        connection = ./modules/connection.nix;
        system = ./modules/system.nix;
        lan = ./modules/lan.nix;
        uplinks = ./modules/uplinks.nix;
        dns = ./modules/dns.nix;
        firewall = ./modules/firewall.nix;
        wifi = ./modules/wifi;
      };

      lib = helpers // {
        devices = import ./lib/devices.nix;
        types = import ./lib/types.nix { inherit lib; };
      };

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          failures = lib.runTests (
            import ./tests {
              inherit
                lib
                terranix
                system
                self
                nixpkgs
                ;
            }
          );
        in
        {
          eval = pkgs.runCommand "nix-routeros-eval" { } ''
            ${
              if failures == [ ] then
                "touch $out"
              else
                "echo ${lib.escapeShellArg (lib.generators.toPretty { } failures)} >&2; exit 1"
            }
          '';
        }
      );

      # Rendered Terraform JSON per shipped profile, consumed by `just validate`
      # (tofu needs the network for providers, so it is not a check).
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          profiles = [
            "hap-ax3"
            "hap-ax2"
            "hap-ac2"
          ];
        in
        {
          validate-configs = pkgs.runCommand "nix-routeros-validate-configs" { } (
            ''
              mkdir $out
            ''
            + lib.concatMapStrings (profile: ''
              mkdir $out/${profile}
              cp ${
                terranix.lib.terranixConfiguration {
                  inherit system;
                  modules = [
                    self.terranixModules.default
                    (./examples/validate + "/${profile}.nix")
                  ];
                }
              } $out/${profile}/config.tf.json
            '') profiles
          );
        }
      );

      # Templates
      templates.default = {
        path = ./templates/default;
        description = "Basic nix-routeros configuration";
      };

      # Formatter — per-system output
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      # Development shell — `nix develop` / direnv `use flake`
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nix
              just
              git
              statix
              deadnix
              nixfmt-tree
              opentofu
              sops
              jq
            ];
          };
        }
      );
    };
}
