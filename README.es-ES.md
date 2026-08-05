

# nix-routeros

[![CI](https://github.com/aleks-sidorenko/nix-routeros/actions/workflows/ci.yml/badge.svg)](https://github.com/aleks-sidorenko/nix-routeros/actions/workflows/ci.yml)

Configuración declarativa de MikroTik RouterOS usando Nix. Define la configuración de tu router con opciones estilo módulo de NixOS, genera JSON de Terraform mediante [terranix](https://terranix.org) y aplícalo con [OpenTofu](https://opentofu.org).

## Inicio Rápido

```bash
# Inicializar desde la plantilla
nix flake init -t github:aleks-sidorenko/nix-routeros

# Edita router.nix con tu configuración de red, luego:
export FLAKE_DIR=$(pwd)
nix run .#default          # Mostrar el JSON generado de Terraform
nix run .#default.plan     # Planificar cambios
nix run .#default.apply    # Aplicar al router
```

## Uso

Agrega nix-routeros como una entrada de flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
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

  outputs = { nixpkgs, nix-routeros, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      packages.${system}.default = nix-routeros.lib.mkRouterDerivation {
        inherit pkgs system;
        modules = [ ./router.nix ];
      };
    };
}
```

Crea `router.nix` con tu configuración:

```nix
{
  routeros = {
    connection.gateway = "10.0.0.1";

    network = {
      subnet = "10.0.0.0/24";
      dhcp.server.range = "10.0.0.50-10.0.0.250";
    };

    bridge.ports = [ "ether2" "ether3" "ether4" "ether5" ];

    hosts.server = {
      ip = "10.0.0.10";
      mac = "AA:BB:CC:DD:EE:FF";
      comment = "Home server";
      aliases = [ "jellyfin" "home-assistant" ];
    };

    wifi = {
      enable = true;
      ssid = "MY-NETWORK";
      country = "united states";
    };
  };
}
```

Para un ejemplo completo de producción con secretos SOPS, WiFi, LTE, reglas personalizadas de firewall y 11 hosts gestionados, consulta [aleks-sidorenko/nix-config/infra/router](https://github.com/aleks-sidorenko/nix-config/tree/master/infra/router).

## Scripts Generados

`mkRouterDerivation` produce una derivación con cuatro scripts (donde `name` por defecto es `"router"`):

| Script | Descripción |
|--------|-------------|
| `<name>-show` | Imprime el JSON generado de Terraform en la salida estándar |
| `<name>-plan` | Ejecuta `tofu init` + `tofu plan` — previsualiza cambios sin aplicarlos |
| `<name>-apply` | Ejecuta `tofu init` + `tofu apply` — aplica cambios al router |
| `<name>-destroy` | Ejecuta `tofu init` + `tofu destroy` — elimina todos los recursos gestionados |

Los scripts `plan`, `apply` y `destroy` requieren que la variable de entorno `FLAKE_DIR` esté establecida en el directorio raíz del flake. Ellos:

1. Desencriptan secretos de SOPS (si `secretsFile` y `secrets` están configurados)
2. Copian el `config.tf.json` generado en `stateDir`
3. Ejecutan `tofu init` y el comando correspondiente

```bash
export FLAKE_DIR=$(pwd)

# Previsualizar qué cambiaría
nix run .#default.plan

# Aplicar cambios al router
nix run .#default.apply

# Inspeccionar el JSON de Terraform sin procesar
nix run .#default | jq .
```

Si usas un `name` personalizado, los scripts se nombran en consecuencia (por ejemplo, `name = "myrouter"` genera `myrouter-show`, `myrouter-plan`, etc.).

## Referencia de Opciones

### `routeros.connection`

| Opción | Tipo | Predeterminado | Descripción |
|--------|------|---------|-------------|
| `gateway` | string | `"10.0.0.1"` | IP del router para la conexión API |
| `username` | string | `"admin"` | Usuario de la API de RouterOS |
| `providerVersion` | string | `"~> 1.99"` | Versión del proveedor de Terraform |
| `scheme` | `"api"` \| `"apis"` | `"api"` | Esquema de conexión API |

### `routeros.system`

| Opción | Tipo | Predeterminado | Descripción |
|--------|------|---------|-------------|
| `identity` | string | `"Router"` | Nombre de host del router |
| `timezone` | string | `"UTC"` | Zona horaria del sistema |
| `services.<name>.enable` | bool | varía | Habilitar/deshabilitar servicio IP |
| `services.<name>.port` | int | varía | Puerto del servicio |
| `services.<name>.allowedAddresses` | string \| null | null | Restringir a subred |
| `ipv6.enable` | bool | `false` | Habilitar IPv6 |
| `macServer.enable` | bool | `true` | Habilitar servidor MAC |
| `neighborDiscovery.enable` | bool | `true` | Habilitar descubrimiento de vecinos |
| `bfd.enable` | bool | `true` | Habilitar BFD |
| `ipsec.dpdInterval` | string | `"2m"` | Intervalo de detección de pares inactivos (DPD) |
| `ipsec.dpdMaxFailures` | int | `5` | Máximo de fallos DPD |

Servicios: `ssh` (22), `winbox` (8291), `api` (8728) habilitados por defecto. `ftp` (21), `telnet` (23), `www` (80), `api-ssl` (8729) deshabilitados por defecto.

### `routeros.network`

| Opción | Tipo | Predeterminado | Descripción |
|--------|------|---------|-------------|
| `subnet` | string | - | CIDR de la red (p. ej. `"10.0.0.0/24"`) |
| `dhcp.server.enable` | bool | - | Habilitar servidor DHCP |
| `dhcp.server.range` | string | - | Rango del grupo (p. ej. `"10.0.0.50-10.0.0.250"`) |
| `dhcp.server.leaseTime` | string | `"1d"` | Duración de la asignación |
| `dhcp.client.enable` | bool | `true` | Cliente DHCP en WAN |
| `dhcp.client.interface` | string | primera WAN | Interfaz del cliente |

### `routeros.bridge`

| Opción | Tipo | Predeterminado | Descripción |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Crear interfaz de puente |
| `ports` | list of string | `[]` | Interfaces a puentear |
| `adminMac` | string \| null | `null` | MAC administrativo manual (null = automático) |

### `routeros.hosts`

Conjunto de atributos de hosts. Cada host es un submódulo:

| Opción | Tipo | Predeterminado | Descripción |
|--------|------|---------|-------------|
| `ip` | string | - | Dirección IP |
| `mac` | string | - | Dirección MAC |
| `comment` | string | `""` | Descripción |
| `dhcp` | bool | `true` | Crear asignación DHCP estática |
| `dns` | bool | `true` | Crear registro A de DNS |
| `aliases` | list of string | `[]` | Nombres DNS adicionales que apuntan a la IP de este host |

Los hosts son la única fuente de verdad: las asignaciones DHCP, los registros A de DNS y los alias se derivan todos de esta opción.

### `routeros.dns`

| Opción | Tipo | Predeterminado | Descripción |
|--------|------|---------|-------------|
| `enable` | bool | - | Habilitar DNS |
| `upstream` | list of string | `["8.8.8.8" "4.4.4.4"]` | Servidores DNS upstream |
| `localDomain` | string | `"local"` | Sufijo de dominio local |
| `aliases` | attrs of string | `{}` | Aliases adicionales (nombre -> host desde `routeros.hosts`) |

### `routeros.firewall`

| Opción | Tipo | Predeterminado | Descripción |
|--------|------|---------|-------------|
| `enable` | bool | - | Habilitar firewall |
| `connectionTracking.udpTimeout` | string | `"10s"` | Tiempo de espera de seguimiento UDP |
| `addressLists` | attrs of (list of string) | `{}` | Listas de direcciones del firewall |
| `filterRules` | list of attrset | `[]` | Reglas de filtro adicionales (agregadas después de la preconfiguración) |
| `natRules` | list of attrset | `[]` | Reglas NAT adicionales (agregadas después de la preconfiguración) |

La preconfiguración incluye 13 reglas de filtro (aceptar establecidas, descartar inválidas, ICMP, loopback, IPsec, fasttrack, descartar DNS WAN) y 2 reglas NAT (enmascarar, redirigir DNS). Las reglas del usuario se agregan después. Las reglas de filtro usan encadenamiento `place_before` para un orden determinista.

### `routeros.wifi`

| Opción | Tipo | Predeterminado | Descripción |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Habilitar WiFi CAPsMAN |
| `ssid` | string | `""` | Nombre de la red |
| `country` | string | `"united states"` | País regulatorio |
| `channels.2g.band` | string | `"2ghz-b/g/n"` | Modo de banda de 2.4GHz |
| `channels.5g.band` | string | `"5ghz-a/n/ac"` | Modo de banda de 5GHz |
| `security.authenticationTypes` | list of string | `["wpa-psk" "wpa2-psk"]` | Tipos de autenticación |
| `security.encryption` | list of string | `["aes-ccm"]` | Métodos de cifrado |

### `routeros.interfaces`

| Opción | Tipo | Predeterminado | Descripción |
|--------|------|---------|-------------|
| `wan` | list of string | `["ether1"]` | Interfaces WAN |
| `lte.enable` | bool | `false` | Habilitar LTE |
| `lte.apn` | string | `""` | APN de LTE |
| `lte.provider` | string | `""` | Nombre del proveedor LTE |

## Preconfiguración

Importa `presets.router` (importado automáticamente por `mkRouterDerivation`) para un router doméstico seguro listo para usar:

- SSH, WinBox, API habilitados y restringidos a la subred LAN
- FTP, Telnet, WWW, API-SSL deshabilitados
- Servidor y cliente DHCP habilitados
- DNS con upstream de Google, dominio `.local`
- Firewall completo con valores predeterminados sensatos
- IPv6 deshabilitado
- WiFi y LTE con activación opcional

Todos los valores de la preconfiguración usan `lib.mkDefault`: anúlalos en tu configuración sin necesidad de `mkForce`.

## Secretos

`mkRouterDerivation` admite [SOPS](https://github.com/getsops/sops) para secretos:

```nix
nix-routeros.lib.mkRouterDerivation {
  inherit pkgs system;
  modules = [ ./router.nix ];
  stateDir = "infra/router";
  secretsFile = "infra/router/secrets.yaml";
  secrets = {
    TF_VAR_routeros_password = "router-api-password";
    TF_VAR_wifi_password = "wifi-password";
    TF_VAR_state_passphrase = "state-passphrase";
  };
};
```

El conjunto de atributos `secrets` mapea nombres de variables de entorno a rutas de clave de SOPS. Los scripts generados los desencriptan en tiempo de ejecución.

## Importación de Recursos Existentes

Para routers ya configurados, crea un `imports.nix` para mapear los IDs de recursos existentes:

```nix
_: {
  import = [
    { to = "routeros_interface_bridge.bridge"; id = "*E"; }
    { to = "routeros_ip_dhcp_server.defconf"; id = "*1"; }
    # Descubre los IDs con: /interface bridge print show-ids
  ];
}
```

Pásalo como módulo:

```nix
modules = [ ./router.nix ./imports.nix ];
```

### Convención de Nomenclatura de Recursos

Los nombres de los recursos de Terraform se derivan de los valores de las opciones mediante una función de sanitización:

- `-` y `.` reemplazados por `_`
- Los nombres que comienzan con un dígito obtienen `_` como prefijo
- Asignaciones DHCP: `routeros_ip_dhcp_server_lease.<nombre_de_host_saneado>`
- Registros DNS: `routeros_ip_dns_record.<nombre_de_host_saneado>`
- Aliases DNS: `routeros_ip_dns_record.alias_<alias_saneado>`

## Salidas del Flake

| Salida | Descripción |
|--------|-------------|
| `terranixModules.default` | Todos los módulos |
| `terranixModules.<module>` | Módulos individuales (connection, system, bridge, interfaces, dhcp, dns, firewall, wifi) |
| `presets.router` | Valores predeterminados con opinión para router doméstico |
| `lib.mkRouterDerivation` | Construye derivación con scripts show/plan/apply/destroy |
| `lib.sanitizeName` | Helper de sanitización de nombres |
| `lib.networkAddress` | Derivar dirección de red desde IP de puerta de enlace |
| `lib.prefixLength` | Extraer longitud de prefijo desde CIDR |
| `templates.default` | Plantilla inicial para `nix flake init` |
| `formatter` | nixfmt-tree |

## Estructura del Repositorio

```
nix-routeros/
├── flake.nix
├── modules/
│   ├── default.nix        # Opciones compartidas (hosts, subnet, _lib)
│   ├── connection.nix     # Proveedor + conexión
│   ├── system.nix         # Identidad, reloj, servicios
│   ├── bridge.nix         # Interfaz de puente + puertos
│   ├── interfaces.nix     # WAN, LTE, listas de interfaces
│   ├── dhcp.nix           # Servidor/cliente DHCP + asignaciones
│   ├── dns.nix            # Registros DNS + reenvío
│   ├── firewall.nix       # Reglas de filtro, NAT, listas de direcciones
│   └── wifi.nix           # Configuración CAPsMAN
├── presets/
│   └── router.nix         # Predeterminados para router doméstico
├── lib/
│   ├── helpers.nix        # sanitizeName, networkAddress, prefixLength
│   └── types.nix          # hostType, firewallRuleType, natRuleType
├── templates/default/     # Plantilla para nix flake init
└── examples/basic/        # Ejemplo mínimo funcional
```

## Licencia

MIT
