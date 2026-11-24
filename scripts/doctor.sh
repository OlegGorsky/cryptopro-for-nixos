#!/usr/bin/env bash
# Диагностика ЭП на NixOS: только чтение, без root, без PIN.
#   bash scripts/doctor.sh [--site host] [--no-mask]
# Печатает OK / WARN / FAIL по слоям. Персональные данные из сертификатов маскируются.
set -uo pipefail

SITE=""
MASK=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE="${2:-}"; shift 2 ;;
    --no-mask) MASK=0; shift ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
  esac
done

NIXLD=/run/current-system/sw/share/nix-ld/lib
CSPLIB=/opt/cprocsp/lib/amd64
GOST=/opt/chromium-gost
fails=0

ok()    { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
warn()  { printf '  \033[33mWARN\033[0m  %s\n' "$*"; }
fail()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fails=$((fails + 1)); }
title() { printf '\n\033[1m%s\033[0m\n' "$*"; }
have()  { command -v "$1" >/dev/null 2>&1; }

mask() {
  if [[ $MASK == 1 ]]; then
    sed -E 's/((CN|SN|G|STREET|L|E|INN|ИНН|SNILS|СНИЛС|OGRNIP|ОГРНИП|ОГРН|OGRN|T|O|OU)=)[^,]*/\1***/g'
  else
    cat
  fi
}

title "1. Система"
if grep -q '^ID=nixos' /etc/os-release 2>/dev/null; then
  ok "NixOS $(. /etc/os-release; echo "${VERSION_ID:-}")"
else
  warn "не NixOS — инструкции репозитория рассчитаны на NixOS"
fi
[[ -e /run/current-system/sw/share/nix-ld ]] && ok "nix-ld включён" || fail "nix-ld не включён (programs.nix-ld.enable)"

title "2. Токен и pcscd"
if have lsusb; then
  usb="$(lsusb | grep -i -E '0a89|aktiv|rutoken' || true)"
  [[ -n "$usb" ]] && ok "USB: $usb" || warn "Рутокен не найден в USB (не вставлен?)"
fi
if systemctl is-active --quiet pcscd.socket || systemctl is-active --quiet pcscd; then
  ok "pcscd активен"
else
  fail "pcscd не активен (services.pcscd.enable)"
fi
if have pcsc_scan; then
  readers="$(timeout 4 pcsc_scan -r 2>/dev/null | grep -E '^ *[0-9]+:' || true)"
  [[ -n "$readers" ]] && ok "считыватели: $(echo "$readers" | tr '\n' ' ')" || warn "pcsc_scan не видит считывателей (токен не вставлен?)"
else
  warn "нет pcsc_scan (pkgs.pcsc-tools)"
fi

title "3. КриптоПро CSP"
if [[ -x /opt/cprocsp/bin/amd64/csptest ]]; then
  ok "CSP распакован в /opt/cprocsp"
else
  fail "нет /opt/cprocsp — CSP не установлен (skills/cryptopro-nixos)"
fi
missing=()
for c in cpconfig csptest certmgr nmcades certprop; do have "$c" || missing+=("$c"); done
[[ ${#missing[@]} -eq 0 ]] && ok "обёртки команд на месте" || fail "нет команд: ${missing[*]} (nixos/cryptopro.nix)"
if have csptest; then
  v="$(csptest -keyset -verifycontext 2>&1 | head -1)"
  [[ "$v" == *"Ver:"* ]] && ok "$v" || fail "csptest: $v"
fi

title "4. Лицензия"
if have cpconfig; then
  lic="$(cpconfig -license -view 2>&1)"
  if grep -q -i -E 'expired|Error code' <<<"$lic"; then
    fail "лицензия недействительна: $(grep -i -E 'expired|Error code' <<<"$lic" | tr '\n' ' ')(skills/cryptopro-license)"
  else
    ok "$(grep -i -E 'expires|permanent|validity' <<<"$lic" | head -2 | tr '\n' ' ')"
  fi
  grep -q '5050N' <<<"$lic" && warn "это демо-ключ из дистрибутива — нужен серийный номер"
fi

title "5. Контейнеры и сертификаты"
if have csptest; then
  conts="$(csptest -keyset -enum_cont -fqcn -verifycontext 2>/dev/null | grep '^\\\\' || true)"
  if [[ -n "$conts" ]]; then
    ok "контейнеров: $(wc -l <<<"$conts")"
  else
    warn "контейнеров нет (токен не вставлен или CSP его не видит)"
  fi
fi
if have certmgr; then
  my="$(certmgr -list -store uMy 2>/dev/null)"
  n="$(grep -c '^Subject' <<<"$my" || true)"
  if [[ "${n:-0}" -gt 0 ]]; then
    ok "сертификатов в uMy: $n"
    grep -E '^(Subject|Not valid after|PrivateKey Link|Embedded License)' <<<"$my" | mask | sed 's/^/        /'
    grep -q 'PrivateKey Link *: No' <<<"$my" && warn "есть сертификат без связи с ключом (skills/rutoken-certificates)"
  else
    warn "uMy пуст — вставь токен; certprop перенесёт сертификат"
  fi
fi
if systemctl --user is-active --quiet cryptopro-certprop 2>/dev/null; then
  ok "служба cryptopro-certprop активна"
else
  warn "cryptopro-certprop не активна: systemctl --user enable --now cryptopro-certprop"
fi

title "6. Native host и расширения"
for f in /etc/opt/chrome/native-messaging-hosts/ru.cryptopro.nmcades.json \
         /etc/chromium/native-messaging-hosts/ru.cryptopro.nmcades.json; do
  if [[ -f "$f" ]]; then
    if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null; then
      ok "$f"
    else
      fail "$f — битый JSON (два определения склеились?)"
    fi
  else
    fail "нет $f"
  fi
done
if [[ -x /opt/cprocsp/bin/amd64/nmcades ]]; then
  nf="$(LD_LIBRARY_PATH=$CSPLIB:$NIXLD ldd /opt/cprocsp/bin/amd64/nmcades 2>/dev/null | grep 'not found' || true)"
  [[ -z "$nf" ]] && ok "nmcades: библиотеки найдены" || fail "nmcades не хватает: $nf"
fi
[[ -f /opt/google/chrome/extensions/pfhgbfnnjiafkhfdkmpiflachepdcjod.json ]] \
  && ok "автоустановка расширения CAdES для Chrome" \
  || warn "нет /opt/google/chrome/extensions/pfhgbfnnjiafkhfdkmpiflachepdcjod.json"

title "7. Браузеры"
if have google-chrome-stable; then ok "$(google-chrome-stable --version 2>/dev/null)"; else warn "Google Chrome не найден"; fi
if [[ -x $GOST/chrome ]]; then
  nf="$(LD_LIBRARY_PATH=$NIXLD ldd $GOST/chrome 2>/dev/null | grep 'not found' || true)"
  if [[ -z "$nf" ]]; then
    ok "$(LD_LIBRARY_PATH=$NIXLD $GOST/chrome --version 2>/dev/null)"
  else
    fail "Chromium-Gost не хватает библиотек: $nf"
  fi
  have chromium-gost && ok "команда chromium-gost есть" || warn "нет обёртки chromium-gost (nixos/cryptopro.nix)"
else
  other="$(ls -d "$HOME"/.local/opt/chromium-gost-* 2>/dev/null | head -1)"
  if [[ -n "$other" ]]; then
    warn "Chromium-Gost стоит в $other, а не в $GOST (skills/chromium-gost)"
  else
    warn "Chromium-Gost не установлен — нужен для ЛК ФНС"
  fi
fi
if pgrep -f 'chromium-gost|/opt/google/chrome/chrome' >/dev/null 2>&1; then
  warn "браузеры запущены — после изменений их нужно полностью закрыть"
fi
if grep -qs '"proxy"' "$HOME/.config/chromium/Default/Preferences"; then
  warn "в профиле ~/.config/chromium есть настройки прокси (known-issues: окно логина прокси)"
fi

title "8. Корень Минцифры"
if grep -q 'MIIFwjCCA6qgAwIBAgICEAAw' /etc/ssl/certs/ca-certificates.crt 2>/dev/null; then
  ok "в системном хранилище"
else
  warn "нет в системном хранилище (nixos/mincifry.nix)"
fi
if have certutil && [[ -d $HOME/.pki/nssdb ]]; then
  if certutil -L -d "sql:$HOME/.pki/nssdb" 2>/dev/null | grep -qi 'russian trusted'; then
    ok "в NSS (~/.pki/nssdb) для Chrome"
  else
    warn "нет в ~/.pki/nssdb (scripts/add-mincifry-nss.sh)"
  fi
else
  warn "NSS не проверен: нет certutil (pkgs.nssTools, ставится nixos/cryptopro.nix) или ~/.pki/nssdb"
fi

if [[ -n "$SITE" ]]; then
  title "9. ГОСТ-TLS ClientHello до $SITE из CSP (без браузера и PIN)"
  if have csptest; then
    out="$(timeout 40 csptest -tlsc -server "$SITE" -port 443 -hello -nocheck -nosave -verbose 2>&1 | tail -6)"
    if grep -q 'ErrorCode: 0x00000000' <<<"$out"; then
      ok "сервер принял ClientHello с ГОСТ-шифрами: сеть и CSP в порядке"
    else
      warn "нет ответа или ошибка: $(tr '\n' ' ' <<<"$out")"
    fi
  fi
fi

if [[ $fails -eq 0 ]]; then
  printf '\nИтог: критичных ошибок нет\n'
else
  printf '\nИтог: FAIL: %s — чини сверху вниз, см. docs/known-issues.md\n' "$fails"
fi
exit 0
