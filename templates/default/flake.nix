{
  description = "My MikroTik router configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    terranix = {
      url = "github:terranix/terranix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-routeros = {
      url = "github:aleks-sidorenko/nix-routeros";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.terranix.follows = "terranix";
    };
  };

  outputs =
    inputs@{ flake-parts, nix-routeros, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [ inputs.terranix.flakeModule ];

      perSystem =
        { pkgs, ... }:
        {
          terranix.terranixConfigurations.router = {
            modules = [
              nix-routeros.terranixModules.default
              ./router.nix
            ];
            workdir = ".";
            terraformWrapper.package = pkgs.opentofu;
          };

          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.opentofu
              pkgs.jq
            ];
          };
        };
    };
}
