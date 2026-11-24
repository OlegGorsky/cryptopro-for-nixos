# Как всё связано

```
 Рутокен (USB)
    │  CCID
    ▼
 pcscd  ◄── services.pcscd + ccid          (/run/pcscd/pcscd.comm)
    │  libpcsclite
    ▼
 КриптоПро CSP  /opt/cprocsp               конфиг: /etc/opt/cprocsp/config64.ini
    │   считыватели: PCSC, rutoken,         лицензия: /etc/opt/cprocsp/license.ini
    │   cryptoki_rutoken (PKCS#11)          ключи на диске: /var/opt/cprocsp/keys/<user>
    │                                       хранилища сертификатов пользователя:
    │                                       /var/opt/cprocsp/users/<user>/stores/*.sto
    ├── certprop (user-служба) — копирует сертификаты с токена в uMy и связывает с ключом
    ├── окно КриптоПро (libcpui + GTK3) — выбор сертификата, ввод PIN
    │
    ├──► nmcades  (native messaging host CAdES)
    │       ▲  JSON-манифест:
    │       │   Chrome:            /etc/opt/chrome/native-messaging-hosts/ru.cryptopro.nmcades.json
    │       │   Chromium/-Gost:    /etc/chromium/native-messaging-hosts/ru.cryptopro.nmcades.json
    │       │
    │   расширение CAdES в браузере (pfhgbfnnjiafkhfdkmpiflachepdcjod)
    │       │
    │   Google Chrome ──► сайты с подписью плагином (Точка, Контур, ...)
    │                     TLS: обычный (RSA/ECDSA) + корень Минцифры в NSS/системе
    │
    └──► Chromium-Gost (msspi → libcapi20 из /opt/cprocsp)
              ГОСТ-TLS с клиентским сертификатом ──► lkipgost2.nalog.ru (ЛК ИП ФНС)
```

## Почему так на NixOS

- В nixpkgs нет КриптоПро (проприетарный, скачивается после входа на cryptopro.ru)
  и нет Chromium-Gost. Поэтому `.deb` **распаковываются** (`dpkg-deb -x`) без
  dpkg-базы и postinst-скриптов; настройку, которую сделал бы postinst, делаем сами
  (`cpconfig -ini ...`, см. `scripts/unpack-cryptopro.sh`).
- Бинарники собраны под обычный Linux (`/lib64/ld-linux-x86-64.so.2`), поэтому
  нужен `programs.nix-ld` и список библиотек.
- Команды CSP (`cpconfig`, `csptest`, `certmgr`, `nmcades`, ...) вызываются через
  обёртки из `nixos/cryptopro.nix`, которые выставляют `LD_LIBRARY_PATH`
  (`/opt/cprocsp/lib/amd64` + nix-ld). Native host в манифесте указывает на
  обёртку `/run/current-system/sw/bin/nmcades`, а не на `/opt/...` напрямую.
- Chromium-Gost можно запускать двумя способами:
  1. **nix-ld напрямую** (текущий рабочий вариант, `nixos/cryptopro.nix`):
     проще, видит все системные пути.
  2. **buildFHSEnv** (`nixos/chromium-gost-fhs.nix`): изолированнее, но нужно
     пробрасывать `/opt/cprocsp`, `/etc/opt/cprocsp`, `/var/opt/cprocsp` (на запись)
     и `/etc/chromium/native-messaging-hosts`, и не забыть `pcsclite` и GTK3.
     Использовался до сентября 2026, потом заменён вариантом 1.

## Где что хранится (для поиска «где моя ЭЦП»)

| Что | Где |
|---|---|
| Закрытый ключ на токене | Внутри Рутокена. Имя контейнера видно в `csptest -keyset -enum_cont -fqcn -verifycontext`: вида `\\.\Aktiv Rutoken lite 00 00\<имя>`, а в сообщениях CSP — `SCARD\rutoken_lt_<id>\...` |
| Ключи, скопированные на диск (если делали) | `/var/opt/cprocsp/keys/<user>/` |
| Личные сертификаты пользователя | хранилище `uMy` → `/var/opt/cprocsp/users/<user>/stores/my.sto` |
| Корневые/промежуточные КриптоПро | `uRoot`/`mRoot`, `uCA`/`mCA` |
| Корни для Chrome | NSS: `~/.pki/nssdb` + системный bundle NixOS |
| Корни для Firefox | `~/.mozilla/firefox/<profile>/cert9.db` |
| Корни системы (curl, Python и т. д.) | `security.pki.certificateFiles` → `/etc/ssl/certs/ca-certificates.crt` |
