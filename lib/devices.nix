# Port and radio layouts follow the product pages:
#   https://mikrotik.com/product/hap_ax3
#   https://mikrotik.com/product/hap_ax2
#   https://mikrotik.com/product/hap_ac2
let
  ether = [
    "ether1"
    "ether2"
    "ether3"
    "ether4"
    "ether5"
  ];
in
{
  hap-ax3 = {
    ethernet = ether;
    defaultUplink = "ether1";
    wifi = {
      stack = "wifi";
      radios = {
        wifi1.band = "5ghz";
        wifi2.band = "2ghz";
      };
    };
    usb = true;
  };
  hap-ax2 = {
    ethernet = ether;
    defaultUplink = "ether1";
    wifi = {
      stack = "wifi";
      radios = {
        wifi1.band = "5ghz";
        wifi2.band = "2ghz";
      };
    };
    usb = false;
  };
  hap-ac2 = {
    ethernet = ether;
    defaultUplink = "ether1";
    wifi = {
      stack = "wireless";
      radios = {
        wlan1.band = "2ghz";
        wlan2.band = "5ghz";
      };
    };
    usb = true;
  };
}
