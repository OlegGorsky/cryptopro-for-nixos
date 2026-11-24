# Контур.Плагин на NixOS.
# Пакеты Контура распакованы из их deb в /opt/kontur.plugin и /opt/kontur.updater.
#   imports = [ ./kontur-plugin.nix ];
{ lib, pkgs, ... }:

let
  nixLdLib = "/run/current-system/sw/share/nix-ld/lib";

  konturPluginWrapper = name: target: pkgs.writeShellScriptBin name ''
    set -euo pipefail
    export LD_LIBRARY_PATH="/opt/kontur.plugin:/opt/kontur.plugin/pkcs11:/opt/cprocsp/lib/amd64:${nixLdLib}:''${LD_LIBRARY_PATH:-}"
    export NIX_LD_LIBRARY_PATH="/opt/kontur.plugin:/opt/kontur.plugin/pkcs11:/opt/cprocsp/lib/amd64:${nixLdLib}:''${NIX_LD_LIBRARY_PATH:-${nixLdLib}}"
    exec "${target}" "$@"
  '';

  konturUpdaterWrapper = name: target: pkgs.writeShellScriptBin name ''
    set -euo pipefail
    export NIX_LD_LIBRARY_PATH="''${NIX_LD_LIBRARY_PATH:-${nixLdLib}}"
    exec "${target}" "$@"
  '';

  manifest = builtins.toJSON {
    name = "kontur.plugin";
    description = "Kontur.Plugin";
    path = "/run/current-system/sw/bin/kontur-plugin-host";
    type = "stdio";
    allowed_origins = [
      "chrome-extension://hnhppcgejeffnbnioloohhmndpmclaga/"
      "chrome-extension://nejicfcnfnecdilmajlppdcgbjilgeec/"
      "chrome-extension://akpjpngckapnibajopggmfhnchfpnkkf/"
      "chrome-extension://momffihklfhkoakghidmkdocdkbfmoac/"
      "chrome-extension://kbeplgmhdbgnbpfkcmndbhjfadkhinhn/"
      "chrome-extension://nhbmmgegnhdhkcclaandbaipceebnckc/"
    ];
  };

  timer = unit: {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0";
      RandomizedDelaySec = "20min";
      Persistent = true;
      Unit = unit;
    };
  };
in
{
  programs.nix-ld.enable = true;

  environment.systemPackages = [
    (konturPluginWrapper "kontur-plugin-host" "/opt/kontur.plugin/kontur.plugin.host")
    (konturPluginWrapper "kontur-plugin-assistant" "/opt/kontur.plugin/kontur.plugin.assistant")
    (konturUpdaterWrapper "kontur-updater" "/opt/kontur.updater/kontur.updater")
  ];

  environment.etc."opt/chrome/native-messaging-hosts/kontur.plugin.json".text = lib.mkDefault manifest;
  environment.etc."opt/edge/native-messaging-hosts/kontur.plugin.json".text = lib.mkDefault manifest;
  environment.etc."chromium/native-messaging-hosts/kontur.plugin.json".text = lib.mkDefault manifest;

  systemd.tmpfiles.rules = [
    "d /etc/opt/skbkontur/plugin 0755 root root -"
    "d /var/tmp/skbkontur/plugin/metrics 0777 root root -"
    "d /opt/kontur.plugin/pkcs11 0755 root root -"
  ];

  systemd.services."kontur.plugin.assistant" = {
    description = "Помощник Контур.Плагин";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/kontur-plugin-assistant";
    };
  };
  systemd.timers."kontur.plugin.assistant" = timer "kontur.plugin.assistant.service";

  systemd.services."kontur.updater" = {
    description = "Контур.Автообновления";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/kontur-updater --package-type=debian";
    };
  };
  systemd.timers."kontur.updater" = timer "kontur.updater.service";
}
