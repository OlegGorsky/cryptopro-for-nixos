# Доверие к корню УЦ Минцифры (Russian Trusted Root CA) на уровне системы.
# Для Chrome/Firefox ещё нужен scripts/add-mincifry-nss.sh (NSS пользователя).
#
# Скопируй certs/russian_trusted_root_ca.pem в /etc/nixos/certs/ и подключи:
#   imports = [ ./mincifry.nix ];
{ ... }:
{
  # Путь — без кавычек. Строка "/etc/nixos/..." в сборку не попадёт.
  security.pki.certificateFiles = [ /etc/nixos/certs/russian_trusted_root_ca.pem ];
}
