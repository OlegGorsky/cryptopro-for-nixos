{ config, lib, pkgs, ... }:

let
  cprocspLib = "/opt/cprocsp/lib/amd64";
  konturPkcs11 = "/opt/kontur.plugin/pkcs11";
  nixLdLib = "/run/current-system/sw/share/nix-ld/lib";

  cryptoproWrapper = name: target: pkgs.writeShellScriptBin name ''
    set -euo pipefail

    export LD_LIBRARY_PATH="${konturPkcs11}:${cprocspLib}:${nixLdLib}:''${LD_LIBRARY_PATH:-}"
    export NIX_LD_LIBRARY_PATH="${konturPkcs11}:${cprocspLib}:${nixLdLib}:''${NIX_LD_LIBRARY_PATH:-${nixLdLib}}"
    export XDG_DATA_DIRS="${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}:${pkgs.gtk3}/share:''${XDG_DATA_DIRS:-/run/current-system/sw/share}"
    export GSETTINGS_SCHEMA_DIR="${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}/glib-2.0/schemas"

    exec "${target}" "$@"
  '';
in
{
  services.pcscd.enable = lib.mkDefault true;

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    alsa-lib
    at-spi2-core
    cairo
    curl
    dbus
    expat
    fontconfig
    freetype
    gcc.cc.lib
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libGL
    libxkbcommon
    libxml2
    nspr
    nss
    openssl
    pango
    pcsc-lite
    stdenv.cc.cc.lib
    zlib
  ];

  environment.systemPackages = [
    (cryptoproWrapper "cpconfig" "/opt/cprocsp/sbin/amd64/cpconfig")
    (cryptoproWrapper "cpinstance" "/opt/cprocsp/sbin/amd64/cpinstance")
    (cryptoproWrapper "csptest" "/opt/cprocsp/bin/amd64/csptest")
    (cryptoproWrapper "certmgr" "/opt/cprocsp/bin/amd64/certmgr")
    (cryptoproWrapper "cryptcp" "/opt/cprocsp/bin/amd64/cryptcp")
    (cryptoproWrapper "cptools" "/opt/cprocsp/bin/amd64/cptools")
    (cryptoproWrapper "certprop" "/opt/cprocsp/bin/amd64/certprop")
    (cryptoproWrapper "nmcades" "/opt/cprocsp/bin/amd64/nmcades")
    (cryptoproWrapper "ocsputil" "/opt/cprocsp/bin/amd64/ocsputil")
    (cryptoproWrapper "tsputil" "/opt/cprocsp/bin/amd64/tsputil")
  ];

  environment.etc."opt/chrome/native-messaging-hosts/ru.cryptopro.nmcades.json".text = ''
    {
      "name": "ru.cryptopro.nmcades",
      "description": "Chrome Native Messaging Host for CAdES Browser plug-in",
      "path": "/run/current-system/sw/bin/nmcades",
      "type": "stdio",
      "allowed_origins": [
        "chrome-extension://iifchhfnnmpdbibifmljnfjhpififfog/",
        "chrome-extension://epebfcehmdedogndhlcacafjaacknbcm/",
        "chrome-extension://pfhgbfnnjiafkhfdkmpiflachepdcjod/"
      ]
    }
  '';

  environment.etc."opt/chrome/policies/managed/cryptopro-for-nixos.json".text = ''
    { "ExtensionManifestV2Availability": 2 }
  '';

  system.activationScripts.cryptoproForNixosChrome = ''
    mkdir -p /opt/google/chrome/extensions
    cat > /opt/google/chrome/extensions/pfhgbfnnjiafkhfdkmpiflachepdcjod.json <<'EOF'
    {
      "external_update_url": "https://clients2.google.com/service/update2/crx"
    }
    EOF
    cat > /opt/google/chrome/extensions/iifchhfnnmpdbibifmljnfjhpififfog.json <<'EOF'
    {
      "external_update_url": "https://clients2.google.com/service/update2/crx"
    }
    EOF
  '';

  systemd.tmpfiles.rules = [
    "d /etc/opt/cprocsp 0755 root root -"
    "d /var/opt/cprocsp 0755 root root -"
    "d /var/opt/cprocsp/users 0755 root root -"
    "d /var/opt/cprocsp/keys 0755 root root -"
    "d /var/opt/cprocsp/tmp 1777 root root -"
  ];

  systemd.user.services.cryptopro-certprop = {
    description = "CryptoPro certificate propagation service";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "/run/current-system/sw/bin/certprop";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}

