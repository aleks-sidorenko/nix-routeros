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
        bridge = ./modules/bridge.nix;
        interfaces = ./modules/interfaces.nix;
        dhcp = ./modules/dhcp.nix;
        dns = ./modules/dns.nix;
        firewall = ./modules/firewall.nix;
        wifi = ./modules/wifi.nix;
      };

      # Presets
      presets.router = ./presets/router.nix;

      # Lib helpers
      lib = helpers // {
        mkRouterDerivation =
          {
            pkgs,
            system,
            name ? "router",
            modules ? [ ],
            stateDir ? ".",
            secretsFile ? null,
            secrets ? { },
          }:
          let
            terraformConfiguration = terranix.lib.terranixConfiguration {
              inherit system;
              extraArgs = { inherit lib pkgs; };
              modules = [ self.presets.router ] ++ modules;
            };

            tofu = "${pkgs.opentofu}/bin/tofu";
            sops = "${pkgs.sops}/bin/sops";

            resolveRoot = ''
              if [[ -z "''${FLAKE_DIR:-}" ]]; then
                echo "Error: FLAKE_DIR not set. Export it to the flake root directory."
                exit 1
              fi
              REPO_ROOT="$FLAKE_DIR"
            '';

            loadSecrets =
              if secretsFile != null && secrets != { } then
                lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (
                    envVar: sopsKey:
                    ''export ${envVar}=$(${sops} -d --extract '["${sopsKey}"]' "$REPO_ROOT/${secretsFile}")''
                  ) secrets
                )
              else
                "";

            tfSetup = ''
              cd "$REPO_ROOT/${stateDir}"
              cp -f ${terraformConfiguration} config.tf.json
            '';

            show = pkgs.writeShellScriptBin "${name}-show" ''
              set -euo pipefail
              cat ${terraformConfiguration} | ${pkgs.jq}/bin/jq
            '';

            plan = pkgs.writeShellScriptBin "${name}-plan" ''
              set -euo pipefail
              ${resolveRoot}
              ${loadSecrets}
              ${tfSetup}
              ${tofu} init -input=false
              ${tofu} plan
            '';

            apply = pkgs.writeShellScriptBin "${name}-apply" ''
              set -euo pipefail
              ${resolveRoot}
              ${loadSecrets}
              ${tfSetup}
              ${tofu} init -input=false
              ${tofu} apply
            '';

            destroy = pkgs.writeShellScriptBin "${name}-destroy" ''
              set -euo pipefail
              ${resolveRoot}
              ${loadSecrets}
              ${tfSetup}
              ${tofu} init -input=false
              ${tofu} destroy
            '';
          in
          show // { inherit plan apply destroy; };
      };

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
