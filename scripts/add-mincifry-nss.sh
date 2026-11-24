#!/usr/bin/env bash
# Добавляет корень Минцифры в NSS пользователя (Chrome, Chromium, Chromium-Gost)
# и во все профили Firefox. Запускать от обычного пользователя, без sudo.
#   bash scripts/add-mincifry-nss.sh [путь-к-сертификату]
set -Eeuo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
cert="${1:-$here/certs/russian_trusted_root_ca.pem}"
name="Russian Trusted Root CA (Минцифры)"
expected="D2:6D:2D:02:31:B7:C3:9F:92:CC:73:85:12:BA:54:10:35:19:E4:40:5D:68:B5:BD:70:3E:97:88:CA:8E:CF:31"

[[ ${EUID:-$(id -u)} -ne 0 ]] || { echo "запускай без sudo — это база текущего пользователя" >&2; exit 1; }
[[ -f "$cert" ]] || { echo "нет файла $cert" >&2; exit 1; }

run() {  # certutil/openssl из системы или через nix-shell
  local tool="$1"; shift
  if command -v "$tool" >/dev/null 2>&1; then
    "$tool" "$@"
  else
    local pkg=nssTools
    [[ "$tool" == openssl ]] && pkg=openssl
    nix-shell -p "$pkg" --run "$tool $(printf '%q ' "$@")"
  fi
}

fp="$(run openssl x509 -in "$cert" -noout -fingerprint -sha256 | cut -d= -f2)"
if [[ "$fp" != "$expected" ]]; then
  echo "SHA-256 не совпадает с ожидаемым:" >&2
  echo "  файл:     $fp" >&2
  echo "  ожидался: $expected" >&2
  echo "Сверь с https://www.gosuslugi.ru/crt и обнови expected, если корень перевыпущен." >&2
  exit 1
fi

add_to() {
  local db="$1"
  if run certutil -L -d "sql:$db" 2>/dev/null | grep -q "Russian Trusted Root CA"; then
    echo "уже есть: $db"
  else
    run certutil -A -n "$name" -t "C,," -d "sql:$db" -i "$cert"
    echo "добавлено: $db"
  fi
}

mkdir -p "$HOME/.pki/nssdb"
[[ -f "$HOME/.pki/nssdb/cert9.db" ]] || run certutil -N -d "sql:$HOME/.pki/nssdb" --empty-password
add_to "$HOME/.pki/nssdb"

for p in "$HOME"/.mozilla/firefox/*/; do
  [[ -f "$p/cert9.db" ]] && add_to "${p%/}"
done

echo "Готово. Полностью перезапусти Chrome / Chromium-Gost / Firefox."
