#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="CryptoPro for NixOS"
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/OlegGorsky/cryptopro-for-nixos/main}"
MODULE_URL="${MODULE_URL:-$RAW_BASE/cryptopro-for-nixos.nix}"
NIXOS_CONFIG="${NIXOS_CONFIG:-/etc/nixos/configuration.nix}"
NIXOS_MODULE_TARGET="${NIXOS_MODULE_TARGET:-/etc/nixos/cryptopro-for-nixos.nix}"
STATE_DIR="/var/lib/cryptopro-for-nixos"
STATE_FILE="$STATE_DIR/state.env"

CSP_PATTERNS=(
  "lsb-cprocsp-base_*.deb"
  "lsb-cprocsp-rdr-64_*.deb"
  "lsb-cprocsp-capilite-64_*.deb"
  "lsb-cprocsp-kc1-64_*.deb"
  "lsb-cprocsp-pkcs11-64_*.deb"
  "lsb-cprocsp-ca-certs_*.deb"
  "cprocsp-curl-64_*.deb"
  "cprocsp-rdr-pcsc-64_*.deb"
  "cprocsp-rdr-rutoken-64_*.deb"
  "cprocsp-rdr-cryptoki-64_*.deb"
  "cprocsp-rdr-gui-gtk-64_*.deb"
  "cprocsp-cptools-gtk-64_*.deb"
  "cprocsp-certprop-64_*.deb"
)

CSP_OPTIONAL_PATTERNS=(
  "ifd-rutokens_*.deb"
  "cprocsp-legacy-64_*.deb"
)

CADES_PATTERNS=(
  "cprocsp-pki-cades-64_*.deb"
  "cprocsp-pki-plugin-64_*.deb"
)

log() {
  printf '\033[1;32m==>\033[0m %s\n' "$*" >&2
}

warn() {
  printf '\033[1;33m!!\033[0m %s\n' "$*" >&2
}

die() {
  printf '\033[1;31mОшибка:\033[0m %s\n' "$*" >&2
  exit 1
}

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "запустите скрипт от root: curl -fsSL $RAW_BASE/install.sh | sudo bash"
  fi
}

target_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s\n' "$SUDO_USER"
  else
    logname 2>/dev/null || printf 'root\n'
  fi
}

target_home() {
  local user="$1"
  getent passwd "$user" | cut -d: -f6
}

check_nixos() {
  [[ -r /etc/os-release ]] || die "не найден /etc/os-release"
  . /etc/os-release
  [[ "${ID:-}" == "nixos" ]] || die "этот скрипт рассчитан только на NixOS, обнаружено: ${PRETTY_NAME:-unknown}"
}

dpkg_deb() {
  if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb "$@"
  elif command -v nix >/dev/null 2>&1; then
    nix shell nixpkgs#dpkg -c dpkg-deb "$@"
  else
    die "нужен dpkg-deb или nix для распаковки .deb"
  fi
}

archive_has_debs() {
  local archive="$1"
  tar -tf "$archive" >/dev/null 2>&1 && tar -tf "$archive" | grep -qE '\.deb$'
}

search_archive() {
  local kind="$1"
  local user home
  user="$(target_user)"
  home="$(target_home "$user")"

  local env_name patterns
  if [[ "$kind" == "csp" ]]; then
    env_name="CSP_ARCHIVE"
    patterns=("linux-amd64*.tgz" "linux-amd64*.tar.gz")
  else
    env_name="CADES_ARCHIVE"
    patterns=("cades-linux-amd64*.tar.gz" "cades-linux-amd64*.tgz")
  fi

  local forced="${!env_name:-}"
  if [[ -n "$forced" ]]; then
    [[ -f "$forced" ]] || die "$env_name указывает на несуществующий файл: $forced"
    archive_has_debs "$forced" || die "$forced не похож на архив с .deb-пакетами"
    printf '%s\n' "$forced"
    return 0
  fi

  local dirs=("$PWD" "$home/Загрузки" "$home/Downloads")
  local found=""
  for pattern in "${patterns[@]}"; do
    found="$(
      find "${dirs[@]}" -maxdepth 3 -type f -name "$pattern" -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr \
        | awk 'NR == 1 { $1=""; sub(/^ /, ""); print }'
    )"
    if [[ -n "$found" ]] && archive_has_debs "$found"; then
      printf '%s\n' "$found"
      return 0
    fi
  done

  return 1
}

download_archive() {
  local kind="$1"
  local url="$2"
  [[ -n "$url" ]] || return 1

  mkdir -p "$STATE_DIR/downloads"
  local out="$STATE_DIR/downloads/${kind}-$(date +%Y%m%d-%H%M%S).tgz"
  log "Скачиваю $kind: $url"
  curl -fL --retry 2 --connect-timeout 20 -o "$out" "$url" || return 1
  archive_has_debs "$out" || die "скачанный файл не является архивом с .deb. Если это страница входа, скачайте архив из личного кабинета КриптоПро и передайте CSP_ARCHIVE/CADES_ARCHIVE."
  printf '%s\n' "$out"
}

extract_archive() {
  local archive="$1"
  local dst="$2"
  mkdir -p "$dst"
  tar -xf "$archive" -C "$dst"
}

find_deb() {
  local root="$1"
  local pattern="$2"
  find "$root" -type f -name "$pattern" | sort -V | tail -n 1
}

version_from_deb() {
  local root="$1"
  local pattern="$2"
  local deb base
  deb="$(find_deb "$root" "$pattern")"
  [[ -n "$deb" ]] || return 1
  base="$(basename "$deb")"
  if [[ "$base" =~ _([0-9][^_]*)_ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    return 1
  fi
}

load_state() {
  CPROCSP_VERSION=""
  CADES_VERSION=""
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$STATE_FILE"
  fi
}

save_state() {
  local csp_version="$1"
  local cades_version="$2"
  mkdir -p "$STATE_DIR"
  cat > "$STATE_FILE" <<EOF
CPROCSP_VERSION="$csp_version"
CADES_VERSION="$cades_version"
EOF
}

installed_csp_version() {
  load_state
  if [[ -n "$CPROCSP_VERSION" ]]; then
    printf '%s\n' "$CPROCSP_VERSION"
    return 0
  fi
  if [[ -x /opt/cprocsp/bin/amd64/csptest ]]; then
    cryptopro_bin csptest -keyset -enum_cont -verifycontext 2>&1 \
      | sed -n 's/.*Release Ver:\([0-9.]*\).*/\1/p' \
      | head -n 1
    return 0
  fi
  return 1
}

installed_cades_version() {
  load_state
  [[ -n "$CADES_VERSION" ]] && printf '%s\n' "$CADES_VERSION"
}

version_is_newer() {
  local candidate="$1"
  local installed="$2"
  [[ -z "$installed" ]] && return 0
  [[ "$candidate" == "$installed" ]] && return 1
  [[ "$(printf '%s\n%s\n' "$installed" "$candidate" | sort -V | tail -n 1)" == "$candidate" ]]
}

should_install_version() {
  local candidate="$1"
  local installed="$2"
  local marker="$3"
  [[ "${FORCE:-0}" == "1" ]] && return 0
  [[ -z "$candidate" ]] && return 0
  [[ ! -e "$marker" ]] && return 0
  version_is_newer "$candidate" "$installed"
}

current_state_versions() {
  load_state
  printf '%s;%s\n' "$CPROCSP_VERSION" "$CADES_VERSION"
}

install_deb_payload() {
  local deb="$1"
  log "Распаковываю $(basename "$deb")"
  dpkg_deb -x "$deb" /
}

install_deb_set() {
  local root="$1"
  shift
  local pattern deb missing=0
  for pattern in "$@"; do
    deb="$(find_deb "$root" "$pattern")"
    if [[ -z "$deb" ]]; then
      warn "Не найден пакет $pattern"
      missing=1
      continue
    fi
    install_deb_payload "$deb"
  done
  return "$missing"
}

install_optional_deb_set() {
  local root="$1"
  shift
  local pattern deb
  for pattern in "$@"; do
    deb="$(find_deb "$root" "$pattern")"
    [[ -n "$deb" ]] && install_deb_payload "$deb"
  done
}

cpconfig_raw() {
  LD_LIBRARY_PATH="/opt/cprocsp/lib/amd64:/run/current-system/sw/share/nix-ld/lib:${LD_LIBRARY_PATH:-}" \
    NIX_LD_LIBRARY_PATH="/opt/cprocsp/lib/amd64:/run/current-system/sw/share/nix-ld/lib:${NIX_LD_LIBRARY_PATH:-/run/current-system/sw/share/nix-ld/lib}" \
    /opt/cprocsp/sbin/amd64/cpconfig "$@"
}

cryptopro_bin() {
  local bin="$1"
  shift
  LD_LIBRARY_PATH="/opt/cprocsp/lib/amd64:/run/current-system/sw/share/nix-ld/lib:${LD_LIBRARY_PATH:-}" \
    NIX_LD_LIBRARY_PATH="/opt/cprocsp/lib/amd64:/run/current-system/sw/share/nix-ld/lib:${NIX_LD_LIBRARY_PATH:-/run/current-system/sw/share/nix-ld/lib}" \
    "/opt/cprocsp/bin/amd64/$bin" "$@"
}

configure_cprocsp() {
  log "Настраиваю CryptoPro CSP"

  mkdir -p /etc/opt/cprocsp /var/opt/cprocsp/users /var/opt/cprocsp/keys /var/opt/cprocsp/tmp
  chmod 1777 /var/opt/cprocsp/tmp

  cpconfig_raw -ini '\config\apppath' -add string libcapi10.so /opt/cprocsp/lib/amd64/libcapi10.so >/dev/null || true
  cpconfig_raw -ini '\config\apppath' -add string librdrfat12.so /opt/cprocsp/lib/amd64/librdrfat12.so >/dev/null || true
  cpconfig_raw -ini '\config\apppath' -add string librdrdsrf.so /opt/cprocsp/lib/amd64/librdrdsrf.so >/dev/null || true
  cpconfig_raw -ini '\config\apppath' -add string libcpui.so /opt/cprocsp/lib/amd64/libcpui.so >/dev/null || true
  cpconfig_raw -ini '\config\apppath' -add string librdrpcsc.so /opt/cprocsp/lib/amd64/librdrpcsc.so >/dev/null || true
  cpconfig_raw -ini '\config\apppath' -add string librdrrutoken.so /opt/cprocsp/lib/amd64/librdrrutoken.so >/dev/null || true
  cpconfig_raw -ini '\config\apppath' -add string librdrcryptoki.so /opt/cprocsp/lib/amd64/librdrcryptoki.so >/dev/null || true
  cpconfig_raw -ini '\config\apppath' -add string libnpcades.so /opt/cprocsp/lib/amd64/libnpcades.so.2 >/dev/null || true

  cpconfig_raw -ini '\config\KeyDevices\PCSC' -add string DLL librdrpcsc.so >/dev/null || true
  cpconfig_raw -ini '\config\KeyDevices\PCSC' -add long Group 1 >/dev/null || true
  cpconfig_raw -ini '\config\KeyDevices\cryptoki_rutoken' -add long Group 1 >/dev/null || true
  cpconfig_raw -ini '\config\KeyDevices\cryptoki_rutoken' -add string DLL librdrcryptoki.so >/dev/null || true
  cpconfig_raw -ini '\config\KeyDevices\cryptoki_rutoken\PNP cryptoki\Default' -add string pkcs11_dll librtpkcs11ecp.so >/dev/null || true

  cpconfig_raw -hardware rndm -add CPSD -name 'CPSD RNG' -level 3 >/dev/null 2>&1 || true
  cpconfig_raw -ini '\config\Random\CPSD\Default' -add string '/db1/kis_1' /var/opt/cprocsp/dsrf/db1/kis_1 >/dev/null || true
  cpconfig_raw -ini '\config\Random\CPSD\Default' -add string '/db2/kis_1' /var/opt/cprocsp/dsrf/db2/kis_1 >/dev/null || true
}

extract_trial_license() {
  local csp_root="$1"
  local deb tmp trial
  deb="$(find_deb "$csp_root" 'lsb-cprocsp-rdr-64_*.deb')"
  [[ -n "$deb" ]] || return 1
  tmp="$(mktemp -d)"
  dpkg_deb -e "$deb" "$tmp" >/dev/null
  trial="$(awk -F= '/^trial_lic=/{print $2}' "$tmp/postinst" 2>/dev/null | tail -n 1 | tr -d '[:space:]')"
  rm -rf "$tmp"
  [[ -n "$trial" ]] || return 1
  printf '%s\n' "$trial"
}

ensure_license() {
  local csp_root="${1:-}"
  if cpconfig_raw -license -view >/dev/null 2>&1; then
    log "Лицензия CryptoPro CSP уже доступна"
    cpconfig_raw -license -view || true
    return 0
  fi

  local trial=""
  if [[ -n "$csp_root" ]]; then
    trial="$(extract_trial_license "$csp_root" || true)"
  fi

  if [[ -z "$trial" ]]; then
    warn "Лицензия CSP недоступна, а demo-серийник не удалось извлечь из пакета."
    warn "Если у вас есть серийный номер, выполните: sudo cpconfig -license -set <серийный_номер>"
    return 1
  fi

  log "Включаю встроенную demo-лицензию из дистрибутива CSP"
  cpconfig_raw -license -set "$trial" -use_expired || true
  cpconfig_raw -license -view || {
    warn "Не удалось активировать demo-лицензию. Возможно, нужен актуальный дистрибутив CSP или ручной серийный номер."
    return 1
  }
}

install_nixos_module() {
  log "Устанавливаю NixOS-модуль"
  mkdir -p "$(dirname "$NIXOS_MODULE_TARGET")"

  if [[ -f "./cryptopro-for-nixos.nix" ]]; then
    install -m 0644 ./cryptopro-for-nixos.nix "$NIXOS_MODULE_TARGET"
  else
    curl -fsSL "$MODULE_URL" -o "$NIXOS_MODULE_TARGET"
    chmod 0644 "$NIXOS_MODULE_TARGET"
  fi

  [[ -f "$NIXOS_CONFIG" ]] || die "не найден $NIXOS_CONFIG"
  if grep -Fq "$NIXOS_MODULE_TARGET" "$NIXOS_CONFIG"; then
    log "Импорт NixOS-модуля уже есть в $NIXOS_CONFIG"
    return 0
  fi

  if ! grep -Eq 'imports[[:space:]]*=' "$NIXOS_CONFIG"; then
    die "не нашёл imports в $NIXOS_CONFIG. Добавьте вручную: imports = [ $NIXOS_MODULE_TARGET ];"
  fi

  local backup="${NIXOS_CONFIG}.backup-cryptopro-for-nixos-$(date +%Y%m%d-%H%M%S)"
  cp -a "$NIXOS_CONFIG" "$backup"
  perl -0pi -e "s|(imports\\s*=\\s*\\[)|\\1\\n    $NIXOS_MODULE_TARGET|" "$NIXOS_CONFIG"
  log "Добавил import в $NIXOS_CONFIG, бэкап: $backup"
}

switch_nixos() {
  if [[ "${NO_REBUILD:-0}" == "1" ]]; then
    warn "NO_REBUILD=1: пропускаю nixos-rebuild switch"
    return 0
  fi

  log "Применяю NixOS-конфигурацию"
  nixos-rebuild switch

  local user
  user="$(target_user)"
  if [[ "$user" != "root" ]]; then
    sudo -u "$user" XDG_RUNTIME_DIR="/run/user/$(id -u "$user")" systemctl --user daemon-reload || true
    sudo -u "$user" XDG_RUNTIME_DIR="/run/user/$(id -u "$user")" systemctl --user enable --now cryptopro-certprop.service || true
  fi
}

install_chrome_files_imperative() {
  log "Проверяю Chrome native messaging и расширение"
  mkdir -p /etc/opt/chrome/native-messaging-hosts /etc/opt/chrome/policies/managed /opt/google/chrome/extensions

  cat > /etc/opt/chrome/native-messaging-hosts/ru.cryptopro.nmcades.json <<'JSON'
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
JSON

  cat > /etc/opt/chrome/policies/managed/cryptopro-for-nixos.json <<'JSON'
{ "ExtensionManifestV2Availability": 2 }
JSON

  cat > /opt/google/chrome/extensions/pfhgbfnnjiafkhfdkmpiflachepdcjod.json <<'JSON'
{
  "external_update_url": "https://clients2.google.com/service/update2/crx"
}
JSON

  cat > /opt/google/chrome/extensions/iifchhfnnmpdbibifmljnfjhpififfog.json <<'JSON'
{
  "external_update_url": "https://clients2.google.com/service/update2/crx"
}
JSON
}

install_archives() {
  local work csp_archive cades_archive csp_root cades_root
  local csp_version cades_version installed_version state_versions
  work="$(mktemp -d)"
  state_versions="$(current_state_versions)"
  local state_csp="${state_versions%%;*}"
  local state_cades="${state_versions#*;}"

  if csp_archive="$(search_archive csp)"; then
    log "Найден CSP-архив: $csp_archive"
  else
    csp_archive="$(download_archive csp "${CSP_URL:-}" || true)"
  fi

  if [[ -n "${csp_archive:-}" ]]; then
    csp_root="$work/csp"
    extract_archive "$csp_archive" "$csp_root"
    csp_version="$(version_from_deb "$csp_root" 'lsb-cprocsp-base_*.deb' || true)"
    installed_version="$(installed_csp_version || true)"
    if should_install_version "$csp_version" "$installed_version" /opt/cprocsp/sbin/amd64/cpconfig; then
      [[ -n "$csp_version" ]] && log "Версия CSP в архиве: $csp_version; установлено: ${installed_version:-нет}"
      install_deb_set "$csp_root" "${CSP_PATTERNS[@]}" || die "в CSP-архиве не хватает обязательных пакетов"
      install_optional_deb_set "$csp_root" "${CSP_OPTIONAL_PATTERNS[@]}"
      state_csp="${csp_version:-$installed_version}"
    else
      log "CSP не новее установленной версии (${installed_version}); пропускаю распаковку пакетов"
    fi
    configure_cprocsp
    ensure_license "$csp_root" || true
  elif [[ ! -x /opt/cprocsp/sbin/amd64/cpconfig ]]; then
    die "CSP не установлен и архив не найден. Скачайте linux-amd64_deb.tgz с cryptopro.ru и запустите: sudo CSP_ARCHIVE=/path/linux-amd64_deb.tgz bash install.sh"
  else
    log "CSP уже установлен, архив не найден - пропускаю установку пакетов CSP"
    configure_cprocsp
    ensure_license "" || true
  fi

  if cades_archive="$(search_archive cades)"; then
    log "Найден CAdES-архив: $cades_archive"
  else
    cades_archive="$(download_archive cades "${CADES_URL:-}" || true)"
  fi

  if [[ -n "${cades_archive:-}" ]]; then
    cades_root="$work/cades"
    extract_archive "$cades_archive" "$cades_root"
    cades_version="$(version_from_deb "$cades_root" 'cprocsp-pki-cades-64_*.deb' || true)"
    installed_version="$(installed_cades_version || true)"
    if should_install_version "$cades_version" "$installed_version" /opt/cprocsp/bin/amd64/nmcades; then
      [[ -n "$cades_version" ]] && log "Версия CAdES в архиве: $cades_version; установлено: ${installed_version:-нет}"
      install_deb_set "$cades_root" "${CADES_PATTERNS[@]}" || die "в CAdES-архиве не хватает обязательных пакетов"
      state_cades="${cades_version:-$installed_version}"
      configure_cprocsp
    else
      log "CAdES не новее установленной версии (${installed_version}); пропускаю распаковку пакетов"
    fi
  elif [[ ! -x /opt/cprocsp/bin/amd64/nmcades ]]; then
    die "CAdES Browser plug-in не установлен и архив не найден. Передайте CADES_ARCHIVE=/path/cades-linux-amd64.tar.gz"
  else
    log "CAdES уже установлен, архив не найден - пропускаю установку CAdES"
  fi

  save_state "$state_csp" "$state_cades"
  rm -rf "$work"
}

token_present() {
  if command -v lsusb >/dev/null 2>&1 && lsusb | grep -qiE '0a89|rutoken|aktiv'; then
    return 0
  fi
  if command -v opensc-tool >/dev/null 2>&1 && opensc-tool --list-readers 2>/dev/null | grep -qiE 'rutoken|aktiv'; then
    return 0
  fi
  return 1
}

install_cert_from_single_container() {
  [[ "${NO_INSTALL_CERT:-0}" == "1" ]] && return 0
  command -v csptest >/dev/null 2>&1 || return 0
  command -v certmgr >/dev/null 2>&1 || return 0

  local containers count
  containers="$(csptest -keyset -enum_cont -fqcn -verifycontext 2>/dev/null | grep '^\\\\' || true)"
  count="$(printf '%s\n' "$containers" | sed '/^$/d' | wc -l | tr -d ' ')"
  [[ "$count" == "1" ]] || return 0

  if certmgr -list -store uMy 2>/dev/null | grep -q 'PrivateKey Link     : Yes'; then
    return 0
  fi

  local cont
  cont="$(printf '%s\n' "$containers" | sed -n '1p')"
  log "Ставлю сертификат из контейнера в uMy"
  certmgr -inst -cont "$cont" || true
}

checkup() {
  log "Чекап $PROJECT"

  local failed=0

  printf '\n[1/7] NixOS: '
  if [[ -r /etc/os-release ]] && grep -q '^ID=nixos' /etc/os-release; then
    echo "ok"
  else
    echo "не NixOS"
    failed=1
  fi

  printf '[2/7] Команды CryptoPro: '
  local cmd missing=()
  for cmd in cpconfig csptest certmgr cryptcp nmcades; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ "${#missing[@]}" -eq 0 ]]; then
    echo "ok"
  else
    echo "нет: ${missing[*]}"
    failed=1
  fi

  printf '[3/7] Лицензия CSP: '
  if command -v cpconfig >/dev/null 2>&1 && cpconfig -license -view >/tmp/cryptopro-license-check.txt 2>&1; then
    echo "ok"
    sed 's/^/      /' /tmp/cryptopro-license-check.txt
  else
    echo "ошибка"
    sed 's/^/      /' /tmp/cryptopro-license-check.txt 2>/dev/null || true
    failed=1
  fi

  printf '[4/7] Chrome native host: '
  if [[ -f /etc/opt/chrome/native-messaging-hosts/ru.cryptopro.nmcades.json ]]; then
    echo "ok"
  else
    echo "нет manifest"
    failed=1
  fi

  printf '[5/7] Расширение Chrome: '
  if [[ -f /opt/google/chrome/extensions/pfhgbfnnjiafkhfdkmpiflachepdcjod.json || -f /opt/google/chrome/extensions/iifchhfnnmpdbibifmljnfjhpififfog.json ]]; then
    echo "ok"
  else
    echo "не настроено автоподключение; расширение можно поставить вручную из Chrome Web Store"
  fi

  printf '[6/7] Рутокен: '
  if token_present; then
    echo "вставлен"
  else
    echo "ключ не вставлен в ноутбук"
    return "$failed"
  fi

  install_cert_from_single_container

  printf '[7/7] Контейнеры и сертификаты:\n'
  if command -v csptest >/dev/null 2>&1; then
    csptest -keyset -enum_cont -fqcn -verifycontext 2>&1 | sed 's/^/      /' || failed=1
  fi
  if command -v certmgr >/dev/null 2>&1; then
    certmgr -list -store uMy 2>&1 | grep -E 'Subject             |SHA1 Thumbprint|PrivateKey Link|Container           |Provider Name' | sed 's/^/      /' || true
  fi

  return "$failed"
}

main_install() {
  need_root
  check_nixos
  mkdir -p "$STATE_DIR"

  install_archives
  install_nixos_module
  install_chrome_files_imperative
  switch_nixos
  checkup

  log "Готово. Перезапустите Google Chrome и установите/включите расширение CAdES Browser plug-in, если Chrome сам его не подтянул."
}

usage() {
  cat <<EOF
$PROJECT

Использование:
  sudo bash install.sh              установить/обновить и выполнить чекап
  bash install.sh check             только чекап

Переменные:
  CSP_ARCHIVE=/path/linux-amd64_deb.tgz
  CADES_ARCHIVE=/path/cades-linux-amd64.tar.gz
  CSP_URL=https://...
  CADES_URL=https://...
  NO_REBUILD=1
  NO_INSTALL_CERT=1
EOF
}

case "${1:-install}" in
  install)
    main_install
    ;;
  check|doctor)
    check_nixos
    checkup
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
