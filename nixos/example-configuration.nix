# Фрагмент /etc/nixos/configuration.nix. Скопируй нужные файлы из nixos/ в /etc/nixos/.
{ config, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./cryptopro.nix            # CSP, CAdES, Chrome, Chromium-Gost, pcscd, certprop
    ./mincifry.nix             # корень Минцифры в системе (нужен /etc/nixos/certs/russian_trusted_root_ca.pem)
    # ./kontur-plugin.nix      # если нужен Контур
    # ./chromium-gost-fhs.nix  # только если nix-ld вариант не подошёл
  ];

  nixpkgs.config.allowUnfree = true;   # google-chrome

  environment.systemPackages = with pkgs; [
    google-chrome
    opensc        # pkcs11-tool, opensc-tool — диагностика токена
  ];
}
