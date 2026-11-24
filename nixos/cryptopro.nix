# КриптоПро CSP + CAdES + Google Chrome + Chromium-Gost на NixOS.
#
# Сами пакеты КриптоПро ставятся распаковкой deb (scripts/unpack-cryptopro.sh),
# Chromium-Gost — scripts/install-chromium-gost.sh. Этот модуль даёт всё, что
# вокруг них: nix-ld, обёртки, pcscd, манифесты native host, политики, certprop.
#
# Подключение: imports = [ ./cryptopro.nix ];
{ config, lib, pkgs, ... }:

let
  cprocspLib = "/opt/cprocsp/lib/amd64";
  konturPkcs11 = "/opt/kontur.plugin/pkcs11";
  nixLdLib = "/run/current-system/sw/share/nix-ld/lib";
  chromiumGostDir = "/opt/chromium-gost";

  # Обёртка для бинарников КриптоПро: библиотеки CSP + nix-ld + схемы GTK
  # (нужны окну выбора сертификата и ввода PIN).
  cryptoproWrapper = name: target: pkgs.writeShellScriptBin name ''
    set -euo pipefail

    export LD_LIBRARY_PATH="${konturPkcs11}:${cprocspLib}:${nixLdLib}:''${LD_LIBRARY_PATH:-}"
    export NIX_LD_LIBRARY_PATH="${konturPkcs11}:${cprocspLib}:${nixLdLib}:''${NIX_LD_LIBRARY_PATH:-${nixLdLib}}"
    export XDG_DATA_DIRS="${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}:${pkgs.gtk3}/share:''${XDG_DATA_DIRS:-/run/current-system/sw/share}"
    export GSETTINGS_SCHEMA_DIR="${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}/glib-2.0/schemas"

    exec "${target}" "$@"
  '';

  # Chromium-Gost из официального deb в /opt/chromium-gost, запуск через nix-ld.
  chromiumGostWrapper = pkgs.writeShellScriptBin "chromium-gost" ''
    set -euo pipefail
    root="${chromiumGostDir}"
    if [[ ! -x "$root/chrome" ]]; then
      echo "Chromium-Gost не установлен: sudo bash scripts/install-chromium-gost.sh" >&2
      exit 1
    fi
    export LD_LIBRARY_PATH="${nixLdLib}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export CHROME_WRAPPER="$root/chromium-gost"
    export CHROME_VERSION_EXTRA=stable
    exec -a "$root/chromium-gost" "$root/chrome" "$@"
  '';

  # Новые имена X11-библиотек в nixpkgs, со старыми как запасным вариантом.
  x11 = name: legacy: pkgs.${name} or pkgs.xorg.${legacy};

  nmcadesManifest = description: builtins.toJSON {
    name = "ru.cryptopro.nmcades";
    inherit description;
    path = "/run/current-system/sw/bin/nmcades";
    type = "stdio";
    allowed_origins = [
      "chrome-extension://iifchhfnnmpdbibifmljnfjhpififfog/"
      "chrome-extension://epebfcehmdedogndhlcacafjaacknbcm/"
      "chrome-extension://pfhgbfnnjiafkhfdkmpiflachepdcjod/"
    ];
  };

  cadesExtension = {
    installation_mode = "normal_installed";
    update_url = "https://clients2.google.com/service/update2/crx";
  };
in
{
  # Рутокен через PC/SC
  services.pcscd.enable = lib.mkDefault true;
  services.pcscd.plugins = lib.mkDefault [ pkgs.ccid ];

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # КриптоПро CSP, CAdES, окно КриптоПро (libcpui, GTK3)
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
    pcsclite
    stdenv.cc.cc.lib
    zlib
  ] ++ [
    # Chromium-Gost
    pkgs.atk
    pkgs.at-spi2-atk
    pkgs.cups
    pkgs.libglvnd
    pkgs.mesa
    (pkgs.libgbm or pkgs.mesa)
    (x11 "libx11" "libX11")
    (x11 "libxcb" "libxcb")
    (x11 "libxcomposite" "libXcomposite")
    (x11 "libxdamage" "libXdamage")
    (x11 "libxext" "libXext")
    (x11 "libxfixes" "libXfixes")
    (x11 "libxrandr" "libXrandr")
    (x11 "libxshmfence" "libxshmfence")
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
    chromiumGostWrapper
    pkgs.pcsc-tools   # pcsc_scan
    pkgs.nssTools     # certutil — корень Минцифры в NSS
  ];

  # mkDefault: если в configuration.nix уже есть свои манифесты, берутся они,
  # а не склейка двух JSON в один файл (тип lines склеивает строки).
  environment.etc."opt/chrome/native-messaging-hosts/ru.cryptopro.nmcades.json".text =
    lib.mkDefault (nmcadesManifest "Chrome Native Messaging Host for CAdES Browser plug-in");

  environment.etc."opt/chrome/policies/managed/cryptopro-for-nixos.json".text =
    lib.mkDefault (builtins.toJSON { ExtensionManifestV2Availability = 2; });

  # Chromium и Chromium-Gost читают /etc/chromium.
  environment.etc."chromium/native-messaging-hosts/ru.cryptopro.nmcades.json".text =
    lib.mkDefault (nmcadesManifest "Chromium Native Messaging Host for CAdES Browser plug-in");

  environment.etc."chromium/policies/managed/cryptopro-for-nixos.json".text = lib.mkDefault (builtins.toJSON {
    ExtensionManifestV2Availability = 2;
    ExtensionSettings."pfhgbfnnjiafkhfdkmpiflachepdcjod" = cadesExtension;
  });

  # Google Chrome подхватывает внешние расширения из /opt/google/chrome/extensions.
  system.activationScripts.cryptoproForNixosChrome = ''
    mkdir -p /opt/google/chrome/extensions
    for id in pfhgbfnnjiafkhfdkmpiflachepdcjod iifchhfnnmpdbibifmljnfjhpififfog; do
      printf '{ "external_update_url": "https://clients2.google.com/service/update2/crx" }\n' \
        > /opt/google/chrome/extensions/$id.json
    done
  '';

  systemd.tmpfiles.rules = [
    "d /etc/opt/cprocsp 0755 root root -"
    "d /var/opt/cprocsp 0755 root root -"
    "d /var/opt/cprocsp/users 0755 root root -"
    "d /var/opt/cprocsp/keys 1777 root root -"
    "d /var/opt/cprocsp/tmp 1777 root root -"
  ];

  # Переносит сертификаты с токена в хранилище uMy и связывает их с ключом.
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
