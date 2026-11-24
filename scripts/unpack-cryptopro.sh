#!/usr/bin/env bash
# Распаковка КриптоПро CSP и CAdES из официальных архивов в / и базовая настройка.
#   sudo bash scripts/unpack-cryptopro.sh [linux-amd64_deb.tgz] [cades-linux-amd64.tar.gz]
# Без аргументов ищет архивы в текущей папке, ~/Загрузки и ~/Downloads.
# Нужен модуль nixos/cryptopro.nix (nix-ld) — иначе cpconfig не запустится.
set -Eeuo pipefail

CSP_PATTERNS=(
  "lsb-cprocsp-base_*.deb" "lsb-cprocsp-rdr-64_*.deb" "lsb-cprocsp-capilite-64_*.deb"
  "lsb-cprocsp-kc1-64_*.deb" "lsb-cprocsp-pkcs11-64_*.deb" "lsb-cprocsp-ca-certs_*.deb"
  "cprocsp-curl-64_*.deb" "cprocsp-rdr-pcsc-64_*.deb" "cprocsp-rdr-rutoken-64_*.deb"
  "cprocsp-rdr-cryptoki-64_*.deb" "cprocsp-rdr-gui-gtk-64_*.deb" "cprocsp-cptools-gtk-64_*.deb"
  "cprocsp-certprop-64_*.deb"
)
CSP_OPTIONAL=( "ifd-rutokens_*.deb" "cprocsp-legacy-64_*.deb" )
CADES_PATTERNS=( "cprocsp-pki-cades-64_*.deb" "cprocsp-pki-plugin-64_*.deb" )

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mОшибка:\033[0m %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "нужен root: sudo bash $0 ..."

user="${SUDO_USER:-root}"
home="$(getent passwd "$user" | cut -d: -f6)"

dpkg_deb() {
  if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb "$@"
  elif command -v nix-shell >/dev/null 2>&1 && nix-instantiate --find-file nixpkgs >/dev/null 2>&1; then
    nix-shell -p dpkg --run "dpkg-deb $(printf '%q ' "$@")"
  else
    nix shell nixpkgs#dpkg -c dpkg-deb "$@"
  fi
}

find_archive() {
  local p
  for p in "$@"; do
    find "$PWD" "$home/Загрузки" "$home/Downloads" -maxdepth 3 -type f -name "$p" -printf '%T@ %p\n' 2>/dev/null
  done | sort -nr | awk 'NR==1 { $1=""; sub(/^ /,""); print }'
}

find_deb() { find "$1" -type f -name "$2" | sort -V | tail -n 1; }

unpack_set() {
  local root="$1" required="$2"; shift 2
  local p deb missing=0
  for p in "$@"; do
    deb="$(find_deb "$root" "$p")"
    if [[ -z "$deb" ]]; then
      [[ "$required" == 1 ]] && { warn "нет пакета $p"; missing=1; }
      continue
    fi
    log "распаковываю $(basename "$deb")"
    dpkg_deb -x "$deb" /
  done
  return "$missing"
}

cpconfig_raw() {
  LD_LIBRARY_PATH="/opt/cprocsp/lib/amd64:/run/current-system/sw/share/nix-ld/lib:${LD_LIBRARY_PATH:-}" \
    /opt/cprocsp/sbin/amd64/cpconfig "$@"
}

configure() {
  log "настраиваю CSP (то, что сделал бы postinst)"
  mkdir -p /etc/opt/cprocsp /var/opt/cprocsp/users /var/opt/cprocsp/keys /var/opt/cprocsp/tmp
  chmod 1777 /var/opt/cprocsp/tmp /var/opt/cprocsp/keys
  local lib
  for lib in libcapi10.so librdrfat12.so librdrdsrf.so libcpui.so librdrpcsc.so librdrrutoken.so librdrcryptoki.so; do
    cpconfig_raw -ini '\config\apppath' -add string "$lib" "/opt/cprocsp/lib/amd64/$lib" >/dev/null || true
  done
  if [[ -e /opt/cprocsp/lib/amd64/libnpcades.so.2 ]]; then
    cpconfig_raw -ini '\config\apppath' -add string libnpcades.so /opt/cprocsp/lib/amd64/libnpcades.so.2 >/dev/null || true
  fi
  cpconfig_raw -ini '\config\KeyDevices\PCSC' -add string DLL librdrpcsc.so >/dev/null || true
  cpconfig_raw -ini '\config\KeyDevices\PCSC' -add long Group 1 >/dev/null || true
  cpconfig_raw -hardware rndm -add CPSD -name 'CPSD RNG' -level 3 >/dev/null 2>&1 || true
  cpconfig_raw -ini '\config\Random\CPSD\Default' -add string '/db1/kis_1' /var/opt/cprocsp/dsrf/db1/kis_1 >/dev/null || true
  cpconfig_raw -ini '\config\Random\CPSD\Default' -add string '/db2/kis_1' /var/opt/cprocsp/dsrf/db2/kis_1 >/dev/null || true
}

csp_archive="${1:-$(find_archive 'linux-amd64*.tgz' 'linux-amd64*.tar.gz')}"
cades_archive="${2:-$(find_archive 'cades-linux-amd64*.tar.gz' 'cades-linux-amd64*.tgz')}"
[[ -f "$csp_archive" ]] || die "не найден архив CSP linux-amd64_deb.tgz (скачай с cryptopro.ru)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

backup="/var/lib/cryptopro-for-nixos/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
[[ -f /etc/opt/cprocsp/config64.ini ]] && cp -a /etc/opt/cprocsp/config64.ini "$backup/"
[[ -d /opt/cprocsp ]] && find /opt/cprocsp -type f | sort > "$backup/opt-cprocsp-files.txt"
log "бэкап конфигурации: $backup"

log "CSP: $csp_archive"
mkdir -p "$work/csp"
tar -xf "$csp_archive" -C "$work/csp"
unpack_set "$work/csp" 1 "${CSP_PATTERNS[@]}" || die "в архиве CSP не хватает обязательных пакетов"
unpack_set "$work/csp" 0 "${CSP_OPTIONAL[@]}" || true

if [[ -f "$cades_archive" ]]; then
  log "CAdES: $cades_archive"
  mkdir -p "$work/cades"
  tar -xf "$cades_archive" -C "$work/cades"
  unpack_set "$work/cades" 1 "${CADES_PATTERNS[@]}" || die "в архиве CAdES не хватает пакетов"
else
  warn "архив CAdES не найден — плагин браузера не обновлялся"
fi

configure

# Первая установка: ставим тот же временный ключ, что ставит postinst официального
# пакета. Истёкший пробный период этим не продлевается (без -use_expired).
if ! cpconfig_raw -license -view >/dev/null 2>&1; then
  rdr="$(find_deb "$work/csp" 'lsb-cprocsp-rdr-64_*.deb')"
  mkdir -p "$work/ctl"
  dpkg_deb -e "$rdr" "$work/ctl" >/dev/null
  trial="$(awk -F= '/^trial_lic=/{print $2}' "$work/ctl/postinst" 2>/dev/null | tail -n1 | tr -d '[:space:]')"
  if [[ -n "$trial" ]]; then
    cpconfig_raw -license -set "$trial" >/dev/null 2>&1 || true
  fi
  if cpconfig_raw -license -view >/dev/null 2>&1; then
    log "включена временная лицензия из дистрибутива"
  else
    warn "лицензии нет: sudo cpconfig -license -set <серийный номер> (skills/cryptopro-license)"
  fi
fi

log "готово. Дальше: nixos-rebuild switch (если модуль ещё не применён), cpconfig -license -view, bash scripts/doctor.sh"
