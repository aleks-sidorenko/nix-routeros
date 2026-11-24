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
    };

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
        passphraseVariable = "wifi_home";
      };
    };
  };
}
