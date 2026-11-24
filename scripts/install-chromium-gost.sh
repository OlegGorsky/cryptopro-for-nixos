#!/usr/bin/env bash
# Установка/обновление Chromium-Gost из официального deb в /opt/chromium-gost.
#   sudo bash scripts/install-chromium-gost.sh                  # последний релиз с GitHub
#   sudo bash scripts/install-chromium-gost.sh path/to/chromium-gost-X-linux-amd64.deb
# Запуск после установки — команда chromium-gost из nixos/cryptopro.nix.
set -Eeuo pipefail

DEST="${CHROMIUM_GOST_DIR:-/opt/chromium-gost}"
REPO="${CHROMIUM_GOST_REPO:-deemru/chromium-gost}"
CACHE="/var/lib/cryptopro-for-nixos/downloads"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mОшибка:\033[0m %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "нужен root: sudo bash $0"

dpkg_deb() {
  if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb "$@"
  elif command -v nix-shell >/dev/null 2>&1 && nix-instantiate --find-file nixpkgs >/dev/null 2>&1; then
    nix-shell -p dpkg --run "dpkg-deb $(printf '%q ' "$@")"
  else
    nix shell nixpkgs#dpkg -c dpkg-deb "$@"
  fi
}

deb="${1:-}"
if [[ -z "$deb" ]]; then
  log "ищу последний релиз $REPO"
  json="$(curl -fsSL --connect-timeout 20 "https://api.github.com/repos/$REPO/releases/latest")" \
    || die "GitHub API недоступен; скачай deb вручную и передай путь"
  url="$(grep -oE '"browser_download_url": *"[^"]*chromium-gost-[^"]*-linux-amd64\.deb"' <<<"$json" | head -n1 | sed -E 's/.*"(https[^"]+)"$/\1/')"
  [[ -n "$url" ]] || die "в релизе нет linux-amd64.deb"
  mkdir -p "$CACHE"
  deb="$CACHE/$(basename "$url")"
  log "качаю $url (с докачкой — GitHub бывает медленным)"
  curl -fL --retry 5 --retry-delay 5 -C - --connect-timeout 20 -o "$deb" "$url" \
    || die "скачивание прервалось — запусти ещё раз, докачается"
  # SHA-256, если он указан в описании релиза рядом с именем файла
  sum="$(grep -oE '[0-9a-f]{64}[^0-9a-f"]{1,40}chromium-gost-[0-9.]+-linux-amd64\.deb' <<<"$json" | head -n1 | grep -oE '^[0-9a-f]{64}' || true)"
  if [[ -n "$sum" ]]; then
    echo "$sum  $deb" | sha256sum -c - >/dev/null || die "SHA-256 не совпал: удали $deb и скачай заново"
    log "SHA-256 совпал"
  else
    warn "SHA-256 в описании релиза не найден — сверь вручную на странице релиза"
  fi
fi
[[ -f "$deb" ]] || die "нет файла $deb"

version=""
[[ "$(basename "$deb")" =~ chromium-gost-([0-9.]+)-linux ]] && version="${BASH_REMATCH[1]}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
log "распаковываю Chromium-Gost ${version}"
dpkg_deb -x "$deb" "$tmp"
[[ -x "$tmp/opt/chromium-gost/chrome" ]] || die "в пакете нет opt/chromium-gost/chrome"

if pgrep -f "$DEST/chrome" >/dev/null 2>&1; then
  warn "Chromium-Gost запущен — после установки закрой его полностью и открой заново"
fi

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST.new" "$DEST.prev"
mv "$tmp/opt/chromium-gost" "$DEST.new"
[[ -d "$DEST" ]] && mv "$DEST" "$DEST.prev"
mv "$DEST.new" "$DEST"
log "установлено в $DEST (предыдущая версия, если была: $DEST.prev)"

# Ярлык для пользователя, который вызвал sudo
user="${SUDO_USER:-}"
if [[ -n "$user" && "$user" != root ]]; then
  home="$(getent passwd "$user" | cut -d: -f6)"
  group="$(id -gn "$user")"
  dir="$home/.local/share/applications"
  file="$dir/chromium-gost.desktop"
  install -d -o "$user" -g "$group" "$home/.local" "$home/.local/share" "$dir"
  if [[ -f "$file" ]] && ! grep -q 'cryptopro-for-nixos' "$file"; then
    cp -a "$file" "$file.backup-$(date +%Y%m%d-%H%M%S)"
  fi
  cat > "$file" <<EOF
[Desktop Entry]
# managed by cryptopro-for-nixos
Version=1.0
Type=Application
Name=Chromium-Gost
GenericName=Web Browser
Comment=Браузер с ГОСТ-TLS для ЛК ФНС
Exec=/run/current-system/sw/bin/chromium-gost %U
Icon=$DEST/product_logo_256.png
Terminal=false
StartupNotify=true
StartupWMClass=chromium-gost
Categories=Network;WebBrowser;
MimeType=text/html;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=Новое окно
Exec=/run/current-system/sw/bin/chromium-gost

[Desktop Action new-private-window]
Name=Новое окно в режиме инкогнито
Exec=/run/current-system/sw/bin/chromium-gost --incognito
EOF
  chown "$user:$group" "$file"
  chmod 0644 "$file"
  log "ярлык: $file"
fi

missing="$(LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib ldd "$DEST/chrome" 2>/dev/null | grep 'not found' || true)"
if [[ -n "$missing" ]]; then
  warn "не хватает библиотек (добавь в programs.nix-ld.libraries):"
  echo "$missing" >&2
else
  log "библиотеки на месте, версия ${version:-?}. Запуск: chromium-gost"
fi
