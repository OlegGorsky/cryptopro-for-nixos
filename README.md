# CryptoPro for NixOS

Скрипт для установки КриптоПро CSP, CAdES Browser plug-in и связки с Google Chrome на NixOS.

Проект не заменяет официальную документацию КриптоПро. Он просто собирает в одном месте шаги, которые нужны на NixOS: распаковку официальных Linux-пакетов, настройку библиотек, `pcscd`, Chrome native messaging и проверку токена.

## Что делает скрипт

- ставит КриптоПро CSP из официального архива `linux-amd64_deb.tgz`;
- ставит КриптоПро ЭЦП Browser plug-in / CAdES из архива `cades-linux-amd64.tar.gz`;
- добавляет NixOS-модуль с обёртками для `cpconfig`, `csptest`, `certmgr`, `cryptcp`, `nmcades` и других команд КриптоПро;
- включает `nix-ld`, нужные библиотеки и `pcscd`;
- настраивает Chrome native messaging host для `ru.cryptopro.nmcades`;
- подключает расширение CAdES для Google Chrome;
- запускает `cryptopro-certprop`, чтобы сертификаты с токена подтягивались в пользовательское хранилище.

Скрипт рассчитан на Google Chrome. Firefox, Chromium, Yandex Browser, Edge и Контур.Плагин здесь не настраиваются.

## Что понадобится

Перед запуском скачайте с официального сайта КриптоПро два архива для Linux x86_64:

- `linux-amd64_deb.tgz` - КриптоПро CSP 5.0;
- `cades-linux-amd64.tar.gz` - КриптоПро ЭЦП Browser plug-in / CAdES.

Положите архивы в `~/Загрузки`, `~/Downloads` или в папку, из которой запускаете скрипт.

## Установка

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

Если репозиторий уже склонирован:

```bash
sudo bash install.sh
```

Скрипт сначала проверяет текущую установку. Если находит более свежие локальные архивы, обновляет пакеты. Если установленная версия не старее найденной, повторно распаковывать пакеты не будет.

## После установки

Перезапустите Google Chrome и проверьте расширение:

- `chrome://extensions`
- `Extension for CAdES Browser Plugin`
- ID: `pfhgbfnnjiafkhfdkmpiflachepdcjod`

Chrome может попросить вручную включить расширение. Это нормально.

Старый ID расширения КриптоПро `iifchhfnnmpdbibifmljnfjhpififfog` тоже разрешён в manifest для совместимости.

## Проверка

Для проверки без установки:

```bash
bash install.sh check
```

Проверка показывает:

- NixOS ли это;
- доступны ли команды КриптоПро;
- видна ли лицензия CSP;
- установлен ли Chrome native messaging manifest;
- вставлен ли Рутокен;
- видны ли контейнеры;
- есть ли у сертификата связка с закрытым ключом.

Если токен не вставлен, проверка отдельно покажет это в выводе.

## Лицензия

В официальных Linux-дистрибутивах КриптоПро CSP есть временная лицензия. Скрипт пытается включить её автоматически.

Постоянный серийный номер вводится отдельно:

```bash
sudo cpconfig -license -set <серийный_номер>
```

Проверить текущую лицензию можно так:

```bash
cpconfig -license -view
```

## Сертификат с токена

Если вставлен один Рутокен и в хранилище `uMy` ещё нет сертификата со связкой на закрытый ключ, скрипт попробует поставить сертификат из контейнера:

```bash
certmgr -inst -cont '<container>'
```

PIN вводится только в окне или терминале КриптоПро. В команду его передавать не нужно.

## Обновления

По умолчанию скрипт ищет архивы в:

- текущей папке;
- `~/Загрузки`;
- `~/Downloads`.

Можно передать прямые ссылки:

```bash
sudo CSP_URL='https://example.org/linux-amd64_deb.tgz' \
     CADES_URL='https://example.org/cades-linux-amd64.tar.gz' \
     bash install.sh
```

Если ссылка ведёт не на архив, а на страницу входа, скрипт остановится и попросит скачать файл вручную.

Полезные переменные:

```bash
CSP_ARCHIVE=/path/to/linux-amd64_deb.tgz
CADES_ARCHIVE=/path/to/cades-linux-amd64.tar.gz
CSP_URL=https://...
CADES_URL=https://...
NO_REBUILD=1
NO_INSTALL_CERT=1
FORCE=1
```

## Полезные ссылки

- Документация КриптоПро: <https://docs.cryptopro.ru/>
- КриптоПро CSP 5.0 R4: <https://cpdn.cryptopro.ru/content/csp50r4/html/titul.html>
- КриптоПро ЭЦП Browser plug-in: <https://www.cryptopro.ru/products/cades/plugin>
- Новость КриптоПро об удалении старого расширения из Chrome Web Store: <https://www.cryptopro.ru/news/2025/02/ob-udalenii-rasshireniya-dlya-cryptopro-etsp-browser-plug-iz-magazina-prilozhenii-googl>
