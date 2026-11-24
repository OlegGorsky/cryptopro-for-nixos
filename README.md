# КриптоПро, Рутокен и браузеры на NixOS — набор для ИИ-агента

Сборник знаний для настройки на **NixOS** электронной подписи на Рутокене:
КриптоПро CSP, ЭЦП Browser plug-in, **Google Chrome** (Точка Банк, Контур) и
**Chromium-Gost** (ЛК ИП ФНС). Это не установщик «в одну кнопку», а инструкции,
модули NixOS, скрипты и разбор реальных ошибок, по которым агент сам разберётся
в вашей машине.

## Как пользоваться

Дайте своему агенту (Claude Code, Codex и т. п.) задание:

> Склонируй https://github.com/OlegGorsky/cryptopro-for-nixos, прочитай AGENTS.md
> и настрой мне ЭП: Chrome для Точки и Chromium-Gost для ЛК ИП ФНС.

Агент начнёт с `AGENTS.md`, запустит диагностику `scripts/doctor.sh` (только
чтение) и дальше пойдёт по нужным скиллам.

Что понадобится от вас:

- архивы КриптоПро с cryptopro.ru (`linux-amd64_deb.tgz`, `cades-linux-amd64.tar.gz`) —
  скачиваются после входа в личный кабинет;
- лицензия КриптоПро CSP (или встроенная в сертификат), если демо-период закончился;
- Рутокен с сертификатом и его PIN — PIN вводите только вы, в окне КриптоПро.

## Коротко о главном

| Задача | Браузер | Ключевое |
|---|---|---|
| ЛК ИП / ФЛ / ЮЛ ФНС, вход по сертификату | **Chromium-Gost** | ГОСТ-TLS; Chrome его не умеет |
| Точка Банк | **Google Chrome** | корень Минцифры в доверенных |
| Контур | Google Chrome | Контур.Плагин |

Подробнее — `docs/sites.md`.

## Что внутри

```
AGENTS.md              точка входа для агента: правила и карта
skills/                пошаговые инструкции по темам (формат SKILL.md)
  diagnostics/         с чего начинать при любой проблеме
  cryptopro-nixos/     установка CSP и CAdES на NixOS
  cryptopro-license/   лицензия: проверка, серийный номер
  rutoken-certificates/ где лежит ЭЦП, контейнеры, PrivateKey Link
  chrome-cades/        Chrome: плагин, Точка, Контур
  chromium-gost/       Chromium-Gost для ЛК ФНС
  mincifry-certs/      сертификаты Минцифры
nixos/                 модули NixOS: cryptopro.nix, mincifry.nix, kontur-plugin.nix, chromium-gost-fhs.nix
scripts/               doctor.sh, unpack-cryptopro.sh, install-chromium-gost.sh, add-mincifry-nss.sh
certs/                 корень Минцифры (с отпечатком для сверки)
docs/                  сайты↔браузеры, известные ошибки, версии, архитектура, источники
install.sh             старый установщик «всё сразу» (оставлен для совместимости)
```

## Проверено на

NixOS 26.05 (unstable), GNOME, КриптоПро CSP 5.0.13003, CAdES 2.0.15700,
Google Chrome 147, Chromium-Gost 150, Рутокен, КЭП от УЦ ФНС.
Подробно — `docs/versions.md`.

## Лицензии

Код и тексты репозитория — MIT, см. [LICENSE](LICENSE). КриптоПро CSP, CAdES,
Контур.Плагин и Chromium-Gost — отдельные продукты со своими лицензиями; их
дистрибутивы в репозиторий не входят. Корневой сертификат Минцифры — публичный,
взят с gosuslugi.ru/crt.
