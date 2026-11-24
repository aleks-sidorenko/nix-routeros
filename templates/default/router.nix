{
  routeros = {
    device = "hap-ax3";

    connection = {
      address = "192.168.88.1";
      username = "admin";
    };

    lan = {
      address = "192.168.88.1/24";
      dhcp.pool = "192.168.88.100-192.168.88.250";
      # leases.server = { mac = "AA:BB:CC:DD:EE:FF"; address = "192.168.88.10"; };
    };

    # The lowest distance that passes its check carries traffic. check.host
    # must be unique per uplink and must not be a DNS upstream.
    uplinks.isp = {
      kind = "ethernet";
      check.host = "1.0.0.1";
    };

    dns.upstream = [ "9.9.9.9" ];

    wifi = {
      country = "United States";
      networks.home = {
        ssid = "home";
        primary = true;
        # Supply the value as TF_VAR_wifi_home.
        passphraseVariable = "wifi_home";
      };
    };
  };
}
