{ config, lib, ... }:
let
  cfg = config.routeros.dns;
in
{
  options.routeros.dns = {
    enable = lib.mkEnableOption "DNS configuration";

    upstream = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "8.8.8.8"
        "4.4.4.4"
      ];
      description = "Upstream DNS servers.";
    };
  };

  config = lib.mkIf cfg.enable {
    resource = {
      routeros_dns.settings = {
        allow_remote_requests = true;
        servers = cfg.upstream;
      };
    };
  };
}
