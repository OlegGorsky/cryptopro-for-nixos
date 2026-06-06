# CryptoPro for NixOS

Автоматизированная установка КриптоПро CSP, CAdES Browser plug-in и Chrome native messaging на NixOS.

Проект появился из рабочей настройки Рутокена для подписи документов в банке на NixOS. В репозитории нет и не должно быть приватных ключей, сертификатов, PIN-кодов, контейнеров, лицензий, `.deb`-пакетов или архивов КриптоПро.

## Что устанавливается

- КриптоПро CSP для Linux из официального архива `linux-amd64_deb.tgz`.
- КриптоПро ЭЦП Browser plug-in / CAdES из архива `cades-linux-amd64.tar.gz`.
- NixOS-модуль с обёртками для `cpconfig`, `csptest`, `certmgr`, `cryptcp`, `nmcades` и других бинарников.
- `nix-ld` и набор библиотек, нужных внешним бинарникам КриптоПро на NixOS.
- `pcscd` для работы со смарт-картами и USB-токенами.
- Chrome native messaging manifest для `ru.cryptopro.nmcades`.
- Автоподключение расширения CAdES для Google Chrome.
- Пользовательский systemd-сервис `cryptopro-certprop`, который подтягивает сертификаты с токена.

Firefox, Chromium, Yandex Browser, Edge и Контур.Плагин намеренно не настраиваются: этот репозиторий делает чистую установку под Google Chrome.

## Быстрый старт

Скачайте официальные архивы КриптоПро:

- `linux-amd64_deb.tgz` — КриптоПро CSP 5.0 для Linux x86_64.
- `cades-linux-amd64.tar.gz` — КриптоПро ЭЦП Browser plug-in / CAdES для Linux x86_64.

Положите их в `~/Загрузки` или `~/Downloads`, затем выполните:

```bash
curl -fsSL https://raw.githubusercontent.com/OlegGorsky/cryptopro-for-nixos/main/install.sh | sudo bash
```

Если архивы лежат в нестандартном месте:

```bash
curl -fsSL https://raw.githubusercontent.com/OlegGorsky/cryptopro-for-nixos/main/install.sh \
  | sudo env CSP_ARCHIVE=/path/to/linux-amd64_deb.tgz \
             CADES_ARCHIVE=/path/to/cades-linux-amd64.tar.gz \
             bash
```

Локальный запуск из клона:

```bash
sudo bash install.sh
```

## Расширение Chrome

После установки перезапустите Google Chrome и проверьте расширение:

- `chrome://extensions`
- расширение: `Extension for CAdES Browser Plugin`
- ID нового расширения: `pfhgbfnnjiafkhfdkmpiflachepdcjod`

Скрипт создаёт Chrome manifest и external extension JSON, но Chrome всё равно может попросить вручную включить расширение. Это нормально.

Старое расширение КриптоПро имело ID `iifchhfnnmpdbibifmljnfjhpififfog`; в manifest оно тоже разрешено для совместимости.

## Проверка

Только чекап:

```bash
bash install.sh check
```

Что проверяется:

- что система действительно NixOS;
- что команды КриптоПро доступны;
- что лицензия CSP читается через `cpconfig -license -view`;
- что Chrome native messaging manifest установлен;
- что Рутокен вставлен;
- что контейнеры видны через `csptest`;
- что сертификат в `uMy` имеет `PrivateKey Link: Yes`.

Если токен не вставлен, скрипт так и напишет: `ключ не вставлен в ноутбук`.

## Лицензия

Официальная документация КриптоПро для Linux говорит: если при установке не введена лицензия, пользователю предоставляется лицензия с ограниченным сроком действия; постоянный серийный номер вводится командой:

```bash
sudo cpconfig -license -set <серийный_номер>
```

Скрипт не хранит серийники. Для demo-режима он извлекает встроенный demo-серийник из `postinst` официального пакета CSP и применяет его через `cpconfig`.

## Установка сертификата с токена

Если вставлен ровно один Рутокен/контейнер и в `uMy` ещё нет сертификата со связкой на приватный ключ, скрипт попробует выполнить:

```bash
certmgr -inst -cont '<container>'
```

PIN не передаётся в командной строке и не сохраняется. Если КриптоПро попросит PIN, вводите его только в системном окне/терминале, не в чат и не в файлы.

## Обновления

Скрипт сначала проверяет, что уже установлено, затем ищет самые свежие локальные архивы в:

- текущей папке;
- `~/Загрузки`;
- `~/Downloads`.

Если переданы `CSP_URL` или `CADES_URL`, скрипт попробует скачать архивы сам. У КриптоПро часть загрузок закрыта авторизацией: если вместо архива скачалась HTML-страница входа, скрипт остановится и попросит скачать архив вручную.

Примеры:

```bash
sudo CSP_URL='https://example.org/linux-amd64_deb.tgz' bash install.sh
sudo CADES_URL='https://example.org/cades-linux-amd64.tar.gz' bash install.sh
```

## Безопасность

В репозиторий не попадают:

- сертификаты;
- закрытые ключи;
- контейнеры;
- PIN;
- серийные номера лицензий;
- подписи документов;
- архивы и `.deb`-пакеты КриптоПро.

`.gitignore` специально закрывает типичные расширения: `.cer`, `.pem`, `.pfx`, `.p12`, `.key`, `.sgn`, `.sig`, `.p7s`, `.deb`, `.rpm`, `.tgz`, `.tar.gz`.

## Полезные ссылки

- Документация КриптоПро: <https://docs.cryptopro.ru/>
- КриптоПро CSP 5.0 R4: <https://cpdn.cryptopro.ru/content/csp50r4/html/titul.html>
- КриптоПро ЭЦП Browser plug-in: <https://www.cryptopro.ru/products/cades/plugin>
- Новость КриптоПро об удалении старого расширения из Chrome Web Store: <https://www.cryptopro.ru/news/2025/02/ob-udalenii-rasshireniya-dlya-cryptopro-etsp-browser-plug-iz-magazina-prilozhenii-googl>
