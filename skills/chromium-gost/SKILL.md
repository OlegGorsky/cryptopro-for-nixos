---
name: chromium-gost
description: Установка и настройка Chromium-Gost на NixOS для сайтов с ГОСТ-TLS, прежде всего ЛК ИП ФНС (lkip2.nalog.ru / lkipgost2.nalog.ru), с КриптоПро CSP, Рутокеном и расширением CAdES. Использовать для входа в ЛК ФНС по сертификату и при ошибке «Проверка защищённого соединения», net_error -113.
---

# Chromium-Gost для ЛК ИП ФНС

## Почему именно он

Вход в ЛК ИП по сертификату идёт через `lkipgost2.nalog.ru` по **ГОСТ-TLS** с
клиентским сертификатом. Google Chrome ГОСТ-шифров не имеет, Яндекс.Браузер на
Linux (Flatpak) их не применяет (`net_error -113`). Chromium-Gost — сборка
Chromium с ГОСТ-TLS через КриптоПро CSP (модуль msspi → `libcapi20`). В nixpkgs
его нет; ставим официальный `.deb`. Официально КриптоПро заявляет его для Astra
и ALT Linux, на NixOS он проверен и работает.

## Требования

- CSP установлен и **лицензия действует** (`skills/cryptopro-license`). Без неё
  ГОСТ-TLS не стартует.
- Рутокен виден (`skills/rutoken-certificates`), сертификат в `uMy` с
  `PrivateKey Link: Yes`.
- Модуль `nixos/cryptopro.nix` применён: в nix-ld есть библиотеки Chromium,
  есть обёртка `chromium-gost` и `/etc/chromium/native-messaging-hosts/ru.cryptopro.nmcades.json`.

## Установка

```bash
sudo bash scripts/install-chromium-gost.sh            # последняя версия с GitHub
sudo bash scripts/install-chromium-gost.sh ~/Загрузки/chromium-gost-156.0.8078.108-linux-amd64.deb
```

Скрипт:
1. берёт `.deb` или скачивает последний релиз `deemru/chromium-gost` (с докачкой —
   GitHub бывает очень медленным);
2. сверяет SHA-256 из описания релиза, если он там есть;
3. распаковывает `opt/chromium-gost` в `/opt/chromium-gost` (старую версию
   переименовывает в `/opt/chromium-gost.prev`);
4. кладёт ярлык `~/.local/share/applications/chromium-gost.desktop` с
   `Exec=/run/current-system/sw/bin/chromium-gost %U` (старый ярлык — в бэкап).

Запуск: команда `chromium-gost` (обёртка из модуля) — выставляет
`LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib` и запускает
`/opt/chromium-gost/chrome`. Профиль — `~/.config/chromium` (общий с обычным Chromium).

Расширение CAdES ставится политикой `/etc/chromium/policies/managed/` из модуля
(`ExtensionSettings`, `normal_installed`).

Если Chromium-Gost раньше распаковывали вручную в домашнюю папку, при переходе на
`/opt/chromium-gost` профиль сохраняется; старую папку можно удалить после проверки.

## Проверка

```bash
LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib ldd /opt/chromium-gost/chrome | grep 'not found'   # пусто
chromium-gost --version
bash scripts/doctor.sh --site lkipgost2.nalog.ru
```

Затем: полностью закрыть все окна Chromium-Gost → открыть `https://lkip2.nalog.ru`
→ «Войти по сертификату» → появится окно КриптоПро с выбором сертификата → PIN
вводит пользователь.

## Если не работает

| Что видно | Куда смотреть |
|---|---|
| Сайт ФНС: «Проверка защищённого соединения с сервером…» | Это шаблон. Проверь лицензию, затем полный перезапуск браузера, затем логи (`chromium-gost --enable-logging=stderr --v=1`) |
| Нет окна выбора сертификата / PIN | Окну КриптоПро не хватает GTK3/`libcpui` в окружении → nix-ld библиотеки |
| «Вставьте носитель», контейнер недоступен только в браузере | Нет `libpcsclite` в окружении процесса |
| Не стартует, `error while loading shared libraries` | `ldd` → добавить недостающее в nix-ld |
| Окно логина прокси | Остатки прокси-расширения в профиле (known-issues) |

## Запасной вариант: FHS

Если nix-ld вариант не подходит, есть `nixos/chromium-gost-fhs.nix`
(`buildFHSEnv`, команда `chromium-gost-fhs`). Так было настроено в августе 2026 —
работает, но легко забыть проброс: `/opt/cprocsp` (ro), `/etc/opt/cprocsp` (ro),
**`/var/opt/cprocsp` (rw!)**, `/etc/chromium/native-messaging-hosts`, плюс
`pcsclite` и GTK3 в `targetPkgs`.

## Обновление

Повтори установку с новым `.deb`. Профиль и расширения сохраняются.
Версия: `chromium-gost --version`. Релизы: https://github.com/deemru/chromium-gost/releases

## Не делать

- Не ставить в Chromium-Gost прокси для ФНС.
- Не запускать с `--no-sandbox` — это не нужно и небезопасно.
