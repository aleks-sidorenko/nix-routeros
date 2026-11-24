# nix-routeros

[![CI](https://github.com/aleks-sidorenko/nix-routeros/actions/workflows/ci.yml/badge.svg)](https://github.com/aleks-sidorenko/nix-routeros/actions/workflows/ci.yml)

A library of [terranix](https://terranix.org) modules that configure a
MikroTik home router through the
[RouterOS Terraform provider](https://registry.terraform.io/providers/terraform-routeros/routeros).
You describe the router with `routeros.*` options, the way you would a NixOS
host, and terranix renders Terraform JSON that OpenTofu applies.

The library holds no site facts: no subnet, SSID, country, APN or upstream DNS
is defaulted. It never reads or stores secret values; they enter as Terraform
variables (see [Secrets](#secrets)).

Version 2 is a breaking release. v1 stays available at tag `v1.0.0`; see
[Migrating from v1](#migrating-from-v1).

## Quick start

```bash
nix flake init -t github:aleks-sidorenko/nix-routeros
$EDITOR router.nix
nix build .#router.config     # render config.tf.json, never touches the router
nix run .#router.plan         # tofu init + plan
nix run .#router              # tofu init + apply
```

`flake.nix` uses terranix's `flakeModule`:

```nix
imports = [ inputs.terranix.flakeModule ];
perSystem = { pkgs, ... }: {
  terranix.terranixConfigurations.router = {
    modules = [ nix-routeros.terranixModules.default ./router.nix ];
    workdir = ".";
    terraformWrapper.package = pkgs.opentofu;
  };
};
```

`examples/basic` is a complete, buildable configuration. State lives in
`workdir` (`terraform.tfstate`); keep it out of the repository or encrypt it
with your own tooling.

## Supported profiles

`routeros.device` is a profile name or an attrset.

| Profile   | Ethernet | Uplink port | Wi-Fi stack | Radios                | USB |
| --------- | -------- | ----------- | ----------- | --------------------- | --- |
| `hap-ax3` | ether1-5 | ether1      | `wifi`      | wifi1 5ghz, wifi2 2ghz | yes |
| `hap-ax2` | ether1-5 | ether1      | `wifi`      | wifi1 5ghz, wifi2 2ghz | no  |
| `hap-ac2` | ether1-5 | ether1      | `wireless`  | wlan1 2ghz, wlan2 5ghz | yes |

For a model not listed, pass the same data as an attrset (`wifi = null` for a
device without radios; `usb` defaults to `false`):

```nix
routeros.device = {
  ethernet = [ "ether1" "ether2" "ether3" "ether4" ];
  defaultUplink = "ether1";
  wifi = {
    stack = "wifi"; # or "wireless"
    radios.wifi1.band = "5ghz";
  };
  usb = false;
};
```

An attrset renders exactly like a named profile with the same data.

## Options

Every option is under `routeros.*`. Evaluation fails with a message naming the
option when a check is violated. Names become Terraform resource keys with `-`
and `.` turned into `_`, so two names differing only in those characters (or a
name equal to a fixed key such as the `bridge_LAN` list member) fail
evaluation instead of overwriting each other.

### connection

| Option | Description |
| --- | --- |
| `address` | Router address the provider connects to. Required, no default. |
| `username` | RouterOS API username (default of the `routeros_username` variable). Required, no default. |
| `scheme` | `api` (default) or `apis`. |
| `providerVersion` | Provider version constraint, default `~> 1.99`. |

### system

`identity` (default `Router`), `timezone` (default `UTC`), and `services.<name>`
for `ssh`, `winbox`, `api` (enabled, limited to the LAN subnet) and `ftp`,
`telnet`, `www`, `api-ssl` (disabled), each with `enable`, `port`,
`allowedAddresses`. Also `ipSettings`, `ipv6`, `macServer` and
`neighborDiscovery` (both limited to the LAN interface list); see
`modules/system.nix`.

### lan

| Option | Description |
| --- | --- |
| `address` | Router address in CIDR, e.g. `192.168.88.1/24`. Required, no default. |
| `subnet` | Read-only network derived from `address`. |
| `ports` | Interfaces bridged into the LAN. Default: the device's ethernet ports minus uplink interfaces; an uplink interface listed here fails evaluation. |
| `dhcp.enable` | Run a DHCP server (default `true`). |
| `dhcp.pool` | Dynamic range, required when DHCP is enabled. |
| `dhcp.leaseTime` | Default `1d`. |
| `leases.<name>` | Static lease: `mac`, `address`, `comment`. The address must be inside the subnet, outside the pool and not the router's. |

### uplinks

`uplinks.<name>` with:

| Option | Description |
| --- | --- |
| `kind` | `ethernet`, `wifi-station`, `lte` or `pppoe`. `lte` needs a device with a USB port. |
| `interface` | Default by kind: the device uplink port, `lte1`, `pppoe-<name>`, `station.radio`. A PPPoE session runs over the device's uplink port. Two uplinks may not share a port, except an ethernet uplink and a PPPoE one. |
| `distance` | Default route distance, default `1`. Distinct per uplink: equal distances would balance traffic (ECMP) instead of failing over. |
| `check.host` | Address pinged to test the uplink. Unique per uplink and not a DNS upstream. |
| `runtimeManaged` | Interface is configured on the router by hand. Required for `wifi-station`. |
| `station.radio` | Radio running a `wifi-station`; its interface is the radio itself. |
| `lte.apn` | APN to set; `null` leaves the router's APN settings alone. |
| `pppoe.user`, `pppoe.passwordVariable` | PPPoE credentials; the password is a Terraform variable. |

Failover: each uplink gets a default route with `check_gateway=ping` towards
its `check.host`, and the host is reachable only through that uplink via a /32
route. The route with the lowest `distance` whose check passes carries
traffic, and the next one takes over when it fails.

### wifi

`wifi.country` (required when any network is defined; no default) and
`wifi.networks.<name>`:

| Option | Description |
| --- | --- |
| `ssid` | Network name. |
| `bands` | `2ghz`, `5ghz`; default both. Every radio of a listed band carries the network. |
| `primary` | Owns the radio interfaces on its bands; others become virtual interfaces. At most one. Without one, the first network by name owns the radios, so adding an earlier-sorting network moves them. |
| `passphraseVariable` | Name of the sensitive Terraform variable holding the passphrase. |

Networks require a device with Wi-Fi hardware. The `wifi` and `wireless`
stacks are chosen from the device profile.

### dns

| Option | Description |
| --- | --- |
| `upstream` | Upstream servers; at least one. |
| `localDomain` | When set, each static lease also resolves as `<lease>.<localDomain>`. |
| `records.<name>` | `type` (`A`, `AAAA`, `CNAME`, `FWD`, `NXDOMAIN`, `TXT`), with `address`, `cname`, `forwardTo` or `text` as the type needs; `matchSubdomain`, `comment`. |

### firewall

| Option | Description |
| --- | --- |
| `defaults` | Include the preset defconf filter and NAT rules, including the DNS redirect (default `true`). The router always answers DNS queries, so with `false` it is an open resolver on the WAN unless your rules drop input from it. |
| `filterRules`, `natRules` | Extra rules appended after the presets; each needs a unique `name`; every other key is a RouterOS attribute passed through (`chain`, `action`, ...). Rule order is the resource order. |
| `addressLists` | Address lists, name to list of addresses; each entry is keyed by list and address. |
| `connectionTracking.udpTimeout` | Default `10s`. |

## Secrets

The library declares Terraform variables and never sees their values. Supply
them as environment variables when you run OpenTofu:

| Variable | Used for |
| --- | --- |
| `TF_VAR_routeros_password` | API password. |
| `TF_VAR_routeros_username` | Optional; defaults to `connection.username`. |
| `TF_VAR_<passphraseVariable>` | One per Wi-Fi network. |
| `TF_VAR_<pppoe.passwordVariable>` | One per PPPoE uplink. |

Variable names must be unique across the configuration; a duplicate fails
evaluation. Load the values with whatever secret manager you use.

## First apply on a reset device

Apply onto a device reset with no default configuration
(`/system reset-configuration no-defaults=yes`). A defconf device already has
the bridge, the `LAN` and `WAN` lists, the DHCP server and bridge ports, so
the first apply fails on them, and its firewall rules would be duplicated.

The provider needs a working connection, and the plan manages the bridge your
session runs over. Before the first apply, create by hand: the `bridge`
interface, a bridge port for the port you are connected through, the bridge's
address (`lan.address`) and an API user with the username and password you
will supply. Then adopt them with `import` blocks in a module of your own;
the bridge port's key is the port name:

```nix
{
  import = [
    { to = "routeros_interface_bridge.bridge"; id = "*1"; }
    { to = "routeros_interface_bridge_port.ether2"; id = "*1"; }
    { to = "routeros_ip_address.lan"; id = "*1"; }
  ];
}
```

Built-in interfaces exist on the device and must be imported too, or the
apply fails creating them: each radio that carries a network or a station
(`routeros_wifi.wifi1`, `routeros_wifi.wifi2` on the `wifi` stack,
`routeros_interface_wireless.wlan1`, `routeros_interface_wireless.wlan2` on
`wireless`) and, for an LTE uplink, `routeros_interface_lte.<uplink>`.

Look up the ids with `print show-ids` in the matching menu, e.g.
`/interface bridge print show-ids`.

## Checks

`nix build .#checks.<system>.eval -L` runs the library's evaluation tests.

## Migrating from v1

| v1 | v2 |
| --- | --- |
| `connection.gateway` | `connection.address` |
| `network.subnet` + `network.gateway` | `lan.address` (CIDR) |
| `network.dhcp.server.range` | `lan.dhcp.pool` |
| `hosts` | `lan.leases` + `dns.localDomain` |
| `dns.aliases` | `dns.records` |
| `bridge.ports` | `lan.ports` (default: all ethernet minus uplinks) |
| `interfaces.wan`, `interfaces.lte` | `uplinks.<name>` |
| `wifi.*` (CAPsMAN) | `wifi.networks.<name>` and `wifi.country` |
| `mkRouterDerivation` | terranix `flakeModule` (`terranixConfigurations`) |
| `presets.router`, `firewall.enable`, `secrets` | removed |

New in v2: `routeros.device` is required, and there are no site defaults, so
`dns.upstream`, `lan.dhcp.pool` and `wifi.country` must be set. The
`state_passphrase` and `wifi_password` variables, sops handling and
`FLAKE_DIR` are gone. v1 stays at tag `v1.0.0`.

## License

See [LICENSE](LICENSE).
