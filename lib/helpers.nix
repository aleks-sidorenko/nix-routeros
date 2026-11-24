{ lib }:
let
  pow2 = n: lib.foldl' (acc: _: acc * 2) 1 (lib.range 1 n);

  ipToInt =
    ip:
    let
      octets = map lib.toInt (lib.splitString "." ip);
    in
    lib.foldl' (acc: o: acc * 256 + o) 0 octets;

  intToIp =
    n:
    lib.concatMapStringsSep "." (shift: toString (lib.mod (n / pow2 shift) 256)) [
      24
      16
      8
      0
    ];

  # Clears the host bits of a /prefix network.
  maskOf = prefix: builtins.bitXor 4294967295 (pow2 (32 - prefix) - 1);

  parseCidr =
    cidr:
    let
      parts = lib.splitString "/" cidr;
      address = builtins.elemAt parts 0;
      prefix = lib.toInt (builtins.elemAt parts 1);
    in
    {
      inherit address prefix;
      network = intToIp (builtins.bitAnd (ipToInt address) (maskOf prefix));
    };
in
{
  inherit parseCidr;

  # "10.0.0.10" "10.0.0.0/24" -> true
  ipInCidr =
    ip: cidr:
    let
      c = parseCidr cidr;
    in
    builtins.bitAnd (ipToInt ip) (maskOf c.prefix) == ipToInt c.network;

  # "10.0.0.120" "10.0.0.100-10.0.0.250" -> true (bounds inclusive)
  ipInRange =
    ip: range:
    let
      bounds = lib.splitString "-" range;
      n = ipToInt ip;
    in
    ipToInt (builtins.elemAt bounds 0) <= n && n <= ipToInt (builtins.elemAt bounds 1);

  # Sanitize a name for use as a Terraform resource identifier.
  # Replaces `-` and `.` with `_`, prepends `_` if name starts with a digit.
  sanitizeName =
    name:
    let
      sanitized = builtins.replaceStrings [ "-" "." ] [ "_" "_" ] name;
    in
    if builtins.match "[0-9].*" sanitized != null then "_${sanitized}" else sanitized;

  # Derive network address from gateway IP (assumes last octet is the host part).
  # "10.0.0.1" -> "10.0.0.0"
  networkAddress =
    gateway:
    let
      parts = lib.splitString "." gateway;
    in
    "${builtins.elemAt parts 0}.${builtins.elemAt parts 1}.${builtins.elemAt parts 2}.0";

  # Extract prefix length from CIDR notation.
  # "10.0.0.0/24" -> 24
  prefixLength =
    cidr:
    let
      parts = lib.splitString "/" cidr;
    in
    lib.toInt (builtins.elemAt parts 1);
}
