# Запасной вариант: Chromium-Gost в изолированном FHS-окружении (buildFHSEnv).
# Основной вариант — запуск через nix-ld (nixos/cryptopro.nix, команда chromium-gost).
# Этот модуль добавляет команду chromium-gost-fhs.
#   imports = [ ./chromium-gost-fhs.nix ];
#
# Уроки, на которых этот файл собран:
#  - без pcsclite CSP внутри окружения не видит Рутокен («вставьте носитель»);
#  - без GTK3 и компании не открывается окно КриптоПро (выбор сертификата, PIN);
#  - /var/opt/cprocsp нужен на ЗАПИСЬ, иначе CSP падает при работе с ключами.
{ pkgs, ... }:

let
  chromiumGostFhs = pkgs.buildFHSEnv {
    name = "chromium-gost-fhs";
    targetPkgs = p: with p; [
      alsa-lib atk at-spi2-atk at-spi2-core cairo cups curl dbus expat fontconfig freetype
      gdk-pixbuf glib gtk3 libGL libdrm libgbm libxkbcommon libxml2 mesa nspr nss openssl
      pango pcsclite systemd vulkan-loader zlib stdenv.cc.cc
      libx11 libxcb libxcomposite libxdamage libxext libxfixes libxrandr libxshmfence
    ];
    extraBwrapArgs = [
      "--ro-bind" "/opt/cprocsp" "/opt/cprocsp"
      "--ro-bind" "/etc/opt/cprocsp" "/etc/opt/cprocsp"
      "--bind" "/var/opt/cprocsp" "/var/opt/cprocsp"
      "--ro-bind-try" "/opt/kontur.plugin" "/opt/kontur.plugin"
      "--dir" "/etc/chromium"
      "--ro-bind" "/etc/chromium/native-messaging-hosts" "/etc/chromium/native-messaging-hosts"
      "--ro-bind-try" "/etc/chromium/policies" "/etc/chromium/policies"
    ];
    runScript = "/opt/chromium-gost/chromium-gost";
  };
in
{
  environment.systemPackages = [ chromiumGostFhs ];
}
