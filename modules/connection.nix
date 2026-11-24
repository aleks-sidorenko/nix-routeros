{ config, lib, ... }:
let
  cfg = config.routeros.connection;
in
{
  options.routeros.connection = {
    address = lib.mkOption {
      type = lib.types.str;
      description = "Router address the provider connects to.";
      example = "10.0.0.1";
    };

    username = lib.mkOption {
      type = lib.types.str;
      description = "RouterOS API username.";
      example = "admin";
    };

    providerVersion = lib.mkOption {
      type = lib.types.str;
      default = "~> 1.99";
      description = "RouterOS Terraform provider version constraint.";
    };

    scheme = lib.mkOption {
      type = lib.types.enum [
        "api"
        "apis"
      ];
      default = "api";
      description = "API connection scheme (api for plaintext, apis for TLS).";
    };
  };

  config = {
    terraform.required_providers.routeros = {
      source = "terraform-routeros/routeros";
      version = cfg.providerVersion;
    };

    provider.routeros = {
      hosturl = "${cfg.scheme}://${cfg.address}";
      username = "\${var.routeros_username}";
      password = "\${var.routeros_password}";
    };

    variable = {
      routeros_username = {
        type = "string";
        default = cfg.username;
        description = "RouterOS API username";
      };
      routeros_password = {
        type = "string";
        sensitive = true;
        description = "RouterOS API password";
      };
    };
  };
}
