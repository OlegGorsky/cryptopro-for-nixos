# Известные проблемы: симптом → причина → исправление

Всё ниже встречалось на практике (NixOS unstable, CSP 5.0.13003, CAdES 2.0.15xxx,
Chrome 147, Chromium-Gost 150).

## Лицензия

| Симптом | Причина | Исправление |
|---|---|---|
| `cpconfig -license -view` → `Error code:3`, `License is expired or not yet valid` | Истёк демо-период (серийник `5050N...` — встроенный пробный ключ) | Ввести купленный серийный номер: `skills/cryptopro-license`. Обходить нельзя |
| `CryptoPro CSP license is not set or corrupted`, «недействительный серийный номер» только в одном браузере | Браузер в песочнице (Flatpak) не видит `/etc/opt/cprocsp/license.ini` | Не использовать Flatpak-браузеры для ЭП; Chromium-Gost и Chrome ставить нативно |
| Лицензия «то есть, то нет» после ручных экспериментов | Рядом с системным `license.ini` лежал старый пользовательский | Действующая лицензия — **системная** `/etc/opt/cprocsp/license.ini`. Лишние копии не использовать |

## Рутокен и контейнеры

| Симптом | Причина | Исправление |
|---|---|---|
| `pcsc_scan` → `No reader found` | Токен не вставлен, или не запущен `pcscd`, или нет драйвера `ccid` | `services.pcscd.enable = true; services.pcscd.plugins = [ pkgs.ccid ];`, переподключить токен |
| Вне браузера контейнер открывается, а внутри Chromium-Gost — «вставьте носитель» / «контейнер недоступен» | В окружении браузера (FHS) не было `libpcsclite` | Добавить `pcsclite` в `nix-ld.libraries` или в `targetPkgs` FHS-окружения |
| `certmgr -list -store uMy` → `PrivateKey Link : No` | Сертификат в хранилище не связан с контейнером на токене | `certmgr -inst -cont '<контейнер>'` или перезапуск `cryptopro-certprop`; см. `skills/rutoken-certificates` |
| CSP/certprop не видят ключи, записанные через PKCS#11 (Рутокен ЭЦП 2.0/3.0) | В `config64.ini` нет считывателя `cryptoki_rutoken` | Добавить `KeyDevices\cryptoki_rutoken` с `pkcs11_dll = librtpkcs11ecp.so`; см. скилл |
| После правки `config64.ini` ничего не изменилось | Работающие процессы (браузер, certprop) держат старую конфигурацию | `systemctl --user restart cryptopro-certprop` и полный перезапуск браузера |

## Chromium-Gost

| Симптом | Причина | Исправление |
|---|---|---|
| Не запускается: `error while loading shared libraries` | Debian-сборка на NixOS не находит библиотеки | Запуск через nix-ld с `LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib` и полным списком библиотек (`nixos/cryptopro.nix`) |
| Не появляется окно выбора сертификата/ввода PIN, в журнале ошибки XCPUI | Окну КриптоПро (`libcpui`, GTK3) не хватает библиотек в окружении браузера | Добавить `gtk3`, `gdk-pixbuf`, `pango`, `cairo`, `at-spi2-*` в nix-ld/FHS |
| В FHS-варианте CSP падает при работе с ключами | `/var/opt/cprocsp` смонтирован только для чтения | В `bwrap` — `--bind /var/opt/cprocsp`, а не `--ro-bind` |
| Сайт ФНС: «Проверка защищённого соединения…», хотя всё настроено | Работает старый процесс браузера, запущенный до исправления | Полностью закрыть браузер (меню → «Выход»), проверить, что процессов из `/opt/chromium-gost` не осталось |
| Постоянно всплывает окно логина прокси, даже без `--proxy-server` | В профиле осталась запись прокси-расширения (fixed proxy) | При закрытом браузере удалить расширение и запись о нём из `~/.config/chromium/Default/Preferences` и `Secure Preferences` |
| ФНС через прокси: `CONNECT ... 502 Bad Gateway` / таймаут | Зарубежный прокси не имеет маршрута до ФНС | Не использовать прокси для ФНС |

## Google Chrome и сайты

| Симптом | Причина | Исправление |
|---|---|---|
| `tochka.com`: `NET::ERR_CERT_AUTHORITY_INVALID`, «https зачёркнут», curl: `self-signed certificate in certificate chain` | Сертификат сайта от УЦ Минцифры, корня нет в доверенных | `skills/mincifry-certs` |
| Плагин CAdES «не установлен» на странице проверки | Нет native host `/etc/opt/chrome/native-messaging-hosts/ru.cryptopro.nmcades.json` или расширения | `nixos/cryptopro.nix`, перезапуск Chrome |
| Старое расширение КриптоПро (`iifchhfnnmpdbibifmljnfjhpififfog`) отключено Chrome | Manifest V2 | Политика `ExtensionManifestV2Availability = 2` и новое расширение `pfhgbfnnjiafkhfdkmpiflachepdcjod` |
| Точка грузится 30+ секунд, в консоли `preload ... not used`, `fallback font` | Разовая задержка на стороне Точки | Ничего не делать, это не ошибка ЭП/TLS |

## NixOS и сборка

| Симптом | Причина | Исправление |
|---|---|---|
| `nixos-rebuild`: путь к сертификату не попал в сборку | В `security.pki.certificateFiles` передана **строка** `"/etc/nixos/certs/x.crt"` | Использовать **путь** без кавычек: `/etc/nixos/certs/x.crt` или `./certs/x.crt` |
| `undefined variable 'pcsc-lite'` | Неверное имя пакета | В nixpkgs он называется `pcsclite` |
| Два модуля задают один `environment.etc."...json".text` → битый JSON | Тип `lines` склеивает строки | В общих модулях задавать значение через `lib.mkDefault` |
| `nix shell nixpkgs#dpkg` долго «unpacking nixpkgs-unstable» | Тянет весь nixpkgs из сети | `nix-shell -p dpkg --run 'dpkg-deb ...'` берёт локальный канал |
| Скачивание релизов с GitHub идёт ~4 МБ/мин и рвётся | Ограничения скорости | `curl -C -` (докачка), сверять SHA-256 из релиза |

## Яндекс.Браузер

| Симптом | Причина | Исправление |
|---|---|---|
| `net_error -113` (cipher mismatch) на ФНС | Flatpak-Яндекс на Linux не делает ГОСТ-TLS даже с лицензией | Использовать Chromium-Gost. Не чинить обёртками |
