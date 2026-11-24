---
name: chrome-cades
description: Настройка Google Chrome на NixOS для работы с ЭП через КриптоПро ЭЦП Browser plug-in (CAdES) и Контур.Плагин — Точка Банк, Контур, Госуслуги. Использовать, когда сайт пишет «плагин не установлен», не видит сертификаты, или для Точки/банков с сертификатом Минцифры.
---

# Google Chrome + CAdES

Chrome — основной браузер для всего, кроме ГОСТ-TLS сайтов (ЛК ФНС → Chromium-Gost).
Подпись в Chrome делает **плагин** (native host `nmcades`), а TLS — обычный.

## Что должно быть

1. **Chrome** из nixpkgs (`google-chrome`), профиль `~/.config/google-chrome`.
2. **Native host** `/etc/opt/chrome/native-messaging-hosts/ru.cryptopro.nmcades.json`:
   ```json
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
   ```
   `path` — обёртка с `LD_LIBRARY_PATH`, не `/opt/cprocsp/bin/amd64/nmcades` напрямую.
3. **Расширение** «CryptoPro Extension for CAdES Browser Plug-in»,
   ID `pfhgbfnnjiafkhfdkmpiflachepdcjod` (MV3). Автоустановка через файл
   `/opt/google/chrome/extensions/pfhgbfnnjiafkhfdkmpiflachepdcjod.json` с
   `external_update_url` (делает модуль). Chrome может попросить включить его вручную.
4. **Политика** `/etc/opt/chrome/policies/managed/*.json`:
   `{ "ExtensionManifestV2Availability": 2 }` — продлевает жизнь старому
   расширению `iifchhfnnmpdbibifmljnfjhpififfog` для сайтов, которые его ждут.
5. **Корень Минцифры** — для Точки и других (`skills/mincifry-certs`).

Всё, кроме самого Chrome и корня, ставит `nixos/cryptopro.nix`.

## Точка Банк

- `tochka.com` с «https зачёркнут» / `ERR_CERT_AUTHORITY_INVALID` → корень Минцифры
  в системе **и** в `~/.pki/nssdb` (Chrome на Linux берёт корни из NSS).
- После установки корня Chrome нужно полностью перезапустить.
- Медленная первая загрузка `/bank/` (~30 с) и сообщения `preload ... not used`,
  `fallback font` — проблемы на стороне Точки, не ЭП.
- Подписание документов в Точке — через расширение CAdES и сертификат из `uMy`
  (`PrivateKey Link: Yes`).

## Контур.Плагин

Проверенный вариант: Контур установлен распаковкой в `/opt/kontur.plugin` и
`/opt/kontur.updater` с обёртками `kontur-plugin-host`, `kontur-plugin-assistant`,
`kontur-updater` (nix-ld + `LD_LIBRARY_PATH` с `/opt/kontur.plugin`,
`/opt/kontur.plugin/pkcs11`, `/opt/cprocsp/lib/amd64`). Манифест
`kontur.plugin.json` прописан для Chrome (`/etc/opt/chrome/...`), Edge
(`/etc/opt/edge/...`) и Chromium (`/etc/chromium/...`), с `allowed_origins`
расширений Контура. `kontur.plugin.assistant` и `kontur.updater` — systemd-службы
с таймерами. Готовый модуль — `nixos/kontur-plugin.nix`.

## Проверка

1. Страница проверки плагина КриптоПро:
   https://www.cryptopro.ru/sites/default/files/products/cades/demopage/cades_bes_sample.html
   — должна показать версию плагина и список сертификатов.
2. Если «плагин не загружен»:
   - `ls -la /etc/opt/chrome/native-messaging-hosts/`;
   - `chrome://extensions` → расширение включено;
   - библиотеки `nmcades` (см. `skills/diagnostics`);
   - Chrome перезапущен полностью.

## Чего не делать

- Не пытаться открыть ЛК ИП ФНС в Chrome — нужен ГОСТ-TLS (`skills/chromium-gost`).
- Не ставить Chrome/Яндекс из Flatpak для ЭП: песочница не видит `/etc/opt/cprocsp`.
