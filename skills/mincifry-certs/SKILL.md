---
name: mincifry-certs
description: Установка корневого сертификата УЦ Минцифры (Russian Trusted Root CA) на NixOS — в системное хранилище, NSS для Chrome/Chromium и Firefox. Использовать при ERR_CERT_AUTHORITY_INVALID, «https зачёркнут», «self-signed certificate in certificate chain» на tochka.com, банках и госсайтах.
---

# Сертификаты Минцифры

Часть российских сайтов (например, **tochka.com**, `www.tochka.com`)
использует TLS-сертификаты от `Russian Trusted Sub CA`, чей корень
`Russian Trusted Root CA` не входит в стандартные хранилища браузеров.

## Откуда брать

Официально — https://www.gosuslugi.ru/crt (корневой и выпускающий). Корень уже
лежит в `certs/russian_trusted_root_ca.pem`. **Перед установкой сверь отпечаток**
с тем, что на Госуслугах:

```bash
openssl x509 -in certs/russian_trusted_root_ca.pem -noout -subject -dates -fingerprint -sha256
# subject= C=RU, O=The Ministry of Digital Development and Communications, CN=Russian Trusted Root CA
# notAfter= Feb 27 21:04:15 2032 GMT
# SHA256 = D2:6D:2D:02:31:B7:C3:9F:92:CC:73:85:12:BA:54:10:35:19:E4:40:5D:68:B5:BD:70:3E:97:88:CA:8E:CF:31
```

Промежуточный (`Russian Trusted Sub CA`) ставить не нужно — сервер отдаёт его в цепочке.

## Куда ставить — три места

### 1. Система (curl, Python — всё, что берёт системный bundle)

```nix
# /etc/nixos/configuration.nix  (или импортировать nixos/mincifry.nix)
security.pki.certificateFiles = [ /etc/nixos/certs/russian_trusted_root_ca.pem ];
```

**Путь без кавычек.** Строка `"/etc/nixos/..."` не попадёт в сборку — на этом уже
спотыкались. Сертификат положить в `/etc/nixos/certs/` заранее.

### 2. Chrome и Chromium-Gost (NSS пользователя)

На Linux Chrome доверяет корням из `~/.pki/nssdb`:

```bash
bash scripts/add-mincifry-nss.sh          # Chrome/Chromium + все профили Firefox
```

Внутри — `certutil -A -n "Russian Trusted Root CA (Минцифры)" -t "C,," -d sql:$HOME/.pki/nssdb -i certs/russian_trusted_root_ca.pem`
(`certutil` из `pkgs.nssTools`).

### 3. Firefox

Отдельная база в каждом профиле `~/.mozilla/firefox/<profile>/cert9.db` — скрипт
обходит их сам.

## Проверка

```bash
curl -sS -o /dev/null -w '%{http_code} ssl_verify=%{ssl_verify_result}\n' https://tochka.com
#  403 ssl_verify=0   ← TLS доверен; 403 — защита Точки от ботов, это нормально
certutil -L -d sql:$HOME/.pki/nssdb | grep -i russian
```

После — полностью перезапустить Chrome.

## КриптоПро

Для TLS в обычном Chrome хранилище КриптоПро (`uRoot`/`mRoot`) не участвует.
Если сайт с ГОСТ-сертификатом Минцифры в Chromium-Gost ругается на цепочку —
поставь корень и туда: `certmgr -inst -store uRoot -file <корень>`
(КриптоПро спросит подтверждение в своём окне).
