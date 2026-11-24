---
name: cryptopro-diagnostics
description: Диагностика ЭП на NixOS по слоям (токен, pcscd, КриптоПро CSP, лицензия, сертификаты, native host, браузер, сайт). Использовать первым при любой жалобе «не работает подпись/вход по ЭП/сайт ФНС/Точка».
---

# Диагностика по слоям

Цель: найти первый сломанный слой, ничего не меняя. Всё ниже — только чтение,
PIN не нужен.

## 1. Быстрый отчёт

```bash
bash scripts/doctor.sh                               # обычный пользователь, без sudo
bash scripts/doctor.sh --site lkipgost2.nalog.ru     # + проверка ГОСТ-TLS до сайта
```

Скрипт печатает по пунктам `OK` / `WARN` / `FAIL`. Иди сверху вниз и чини первый `FAIL`.

## 2. Ручная проверка, если скрипта нет

```bash
# Токен и считыватель
lsusb | grep -i -E '0a89|aktiv|rutoken'          # 0a89:xxxx — Рутокен
systemctl status pcscd --no-pager
pcsc_scan -r                                     # список считывателей (pkgs.pcsc-tools)

# CSP и лицензия
csptest -keyset -verifycontext | head -1         # версия CSP, ErrorCode 0
cpconfig -license -view                          # Error code:3 = лицензия истекла

# Контейнеры и сертификаты (PIN не спрашивает)
csptest -keyset -enum_cont -fqcn -verifycontext
certmgr -list -store uMy | grep -E 'Subject|Not valid after|Container|PrivateKey Link'

# Служба переноса сертификатов с токена
systemctl --user status cryptopro-certprop --no-pager

# Native host и расширение
cat /etc/opt/chrome/native-messaging-hosts/ru.cryptopro.nmcades.json
cat /etc/chromium/native-messaging-hosts/ru.cryptopro.nmcades.json
LD_LIBRARY_PATH=/opt/cprocsp/lib/amd64:/run/current-system/sw/share/nix-ld/lib \
  ldd /opt/cprocsp/bin/amd64/nmcades | grep 'not found'   # пусто = библиотеки на месте

# Chromium-Gost
LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib ldd /opt/chromium-gost/chrome | grep 'not found'
```

Маскируй в отчёте ФИО, ИНН, СНИЛС, ОГРНИП из вывода `certmgr`.

## 3. Журналы — где смотреть

| Что | Команда |
|---|---|
| Ошибки CSP, окна КриптоПро (XCPUI), лицензии | `journalctl --since -1h \| grep -i -E 'cprocsp\|capi\|cpui\|license'` |
| pcscd, Рутокен | `journalctl -u pcscd --since -1h` |
| certprop | `journalctl --user -u cryptopro-certprop --since -1d` |
| Сетевые ошибки Chromium-Gost/Chrome | запусти браузер из терминала с `--enable-logging=stderr --v=1` и смотри `net_error`, `SSL`, `msspi` |
| Контур.Плагин | `journalctl -u kontur.plugin.assistant -u kontur.updater` |
| Прошлые сессии агентов | история Codex/Claude пользователя: искать `cprocsp`, `chromium-gost`, `nmcades` |
| Бэкапы прошлых настроек | `/etc/nixos/configuration.nix.backup-*`, `/var/lib/cryptopro-for-nixos/backups/` и папки с бэкапами, которые делал пользователь или прошлый агент |

Журнал systemd хранится недолго — воспроизводи ошибку и смотри сразу.

## 4. Как интерпретировать

- Сайт ФНС показывает «Проверка защищённого соединения…» — это шаблон, не причина.
  Причину ищи в слоях выше и в логах браузера.
- `net_error -113` / `ERR_SSL_VERSION_OR_CIPHER_MISMATCH` на ФНС — у браузера нет
  ГОСТ-TLS: не тот браузер, или Chromium-Gost не видит CSP/лицензию.
- `ERR_CERT_AUTHORITY_INVALID` на банке/госсайте — нет корня Минцифры.
- Всё зелёное, а в браузере старая ошибка — браузер не перезапускали полностью.

Дальше — таблица `docs/known-issues.md` и профильный скилл.
