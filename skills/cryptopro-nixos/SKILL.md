---
name: cryptopro-nixos
description: Установка и обновление КриптоПро CSP 5.0 и ЭЦП Browser plug-in (CAdES) на NixOS распаковкой официальных deb, настройка nix-ld, обёрток команд, pcscd и native host. Использовать при первичной установке, обновлении версии или если команды cpconfig/csptest/nmcades не запускаются.
---

# КриптоПро CSP + CAdES на NixOS

## Что нужно от пользователя

Архивы с cryptopro.ru (скачиваются только после входа, агент сам скачать не сможет):

- `linux-amd64_deb.tgz` — КриптоПро CSP 5.0 для Linux x64, deb;
- `cades-linux-amd64.tar.gz` — ЭЦП Browser plug-in.

Обычно лежат в `~/Загрузки` или `~/Downloads`. Попроси пользователя скачать,
если их нет. **Архивы и `.deb` не коммить** (они проприетарные, см. `.gitignore`).

## Шаги

### 1. Модуль NixOS

Скопируй `nixos/cryptopro.nix` в `/etc/nixos/cryptopro.nix` и добавь в `imports`
(пример — `nixos/example-configuration.nix`). Модуль включает:

- `services.pcscd` (+ `ccid`), `programs.nix-ld` с нужными библиотеками;
- обёртки `cpconfig csptest certmgr cryptcp cptools certprop nmcades ocsputil tsputil cpinstance`;
- манифесты native host для Chrome и Chromium/Chromium-Gost, политики расширения;
- обёртку `chromium-gost`, `pcsc_scan`, `certutil`;
- user-службу `cryptopro-certprop`;
- каталоги `/var/opt/cprocsp/*` через tmpfiles.

Если в `configuration.nix` уже есть свои определения того же (например, КриптоПро
раньше настраивали вручную), модуль им уступает (`lib.mkDefault` для
манифестов). Обёртки и nix-ld просто объединятся. Перед подключением сравни.

### 2. Распаковка пакетов

```bash
sudo bash scripts/unpack-cryptopro.sh ~/Загрузки/linux-amd64_deb.tgz ~/Загрузки/cades-linux-amd64.tar.gz
```

Скрипт делает бэкап `config64.ini` и списка файлов `/opt/cprocsp`, распаковывает
только нужные пакеты (список — `docs/versions.md`) в `/` и делает настройку,
которую обычно делает postinst:

```bash
cpconfig -ini '\config\apppath' -add string libcapi10.so /opt/cprocsp/lib/amd64/libcapi10.so
# ... librdrfat12, librdrdsrf, libcpui, librdrpcsc, librdrrutoken, librdrcryptoki, libnpcades
cpconfig -ini '\config\KeyDevices\PCSC' -add string DLL librdrpcsc.so
cpconfig -hardware rndm -add CPSD -name 'CPSD RNG' -level 3
```

При первой установке он включает временную лицензию из дистрибутива — так же,
как официальный пакет.

### 3. Применить

```bash
sudo nixos-rebuild switch          # только с согласия пользователя
systemctl --user daemon-reload
systemctl --user enable --now cryptopro-certprop
```

### 4. Проверить

```bash
csptest -keyset -verifycontext | head -1     # CSP v5.0..., ErrorCode 0x00000000
cpconfig -license -view                      # см. skills/cryptopro-license
bash scripts/doctor.sh
```

## Тонкости

- Распаковка через `dpkg-deb`: если его нет, используй `nix-shell -p dpkg --run`
  (локальный канал, быстро), а не `nix shell nixpkgs#dpkg` (качает весь nixpkgs).
- Скрипты из пакетов (`/etc/init.d/cprocsp`, postinst) рассчитаны на Debian
  (`PATH=/usr/bin:/bin`, `lsb_release`) — на NixOS их не запускай, делай настройку
  `cpconfig` вручную.
- После обновления CSP/CAdES перезапусти `cryptopro-certprop` и браузеры.
- `librtpkcs11ecp.so` (PKCS#11 Рутокена) есть в составе Контур.Плагина
  (`/opt/kontur.plugin/pkcs11/librtpkcs11ecp.so`) или на rutoken.ru. Нужен для ключей, записанных через PKCS#11 (Рутокен ЭЦП 2.0/3.0),
  см. `skills/rutoken-certificates`.
