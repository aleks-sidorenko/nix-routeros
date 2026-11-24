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
    dns.upstream = [ "9.9.9.9" ];
    uplinks.isp = {
      kind = "ethernet";
      check.host = "1.0.0.1";
    };
    uplinks.hotspot = {
      kind = "wifi-station";
      runtimeManaged = true;
      station.radio = "wifi2";
      distance = 2;
      check.host = "1.1.1.1";
    };
    wifi = {
      country = "United States";
      networks.home = {
        ssid = "home";
        primary = true;
        passphraseVariable = "wifi_home";
      };
      networks.guest = {
        ssid = "guest";
        bands = [ "2ghz" ];
        passphraseVariable = "wifi_guest";
      };
    };
  };
}
