---
name: rutoken-certificates
description: Где на NixOS хранится ЭЦП (Рутокен, контейнеры КриптоПро, хранилища сертификатов), как найти контейнер, связать сертификат с ключом (PrivateKey Link), настроить certprop и считыватели PCSC/PKCS#11. Использовать при «не видит ключ/сертификат», «вставьте носитель», PrivateKey Link: No.
---

# Рутокен, контейнеры и сертификаты

## Где лежит ЭЦП

- **Закрытый ключ** — на Рутокене, в контейнере КриптоПро. С токена не
  извлекается, копировать его не нужно.
- **Сертификат** — тоже в контейнере на токене; копия кладётся в личное
  хранилище пользователя `uMy` (`/var/opt/cprocsp/users/<user>/stores/my.sto`).
  Связь «сертификат → контейнер» и делает подпись возможной.
- Если ключ когда-то копировали на диск — он в `/var/opt/cprocsp/keys/<user>/`.

## Найти контейнер и сертификат (без PIN)

```bash
pcsc_scan -r                                         # считыватель виден?
csptest -keyset -enum_cont -fqcn -verifycontext      # список контейнеров
certmgr -list -store uMy | grep -E 'Subject|Issuer|Not valid after|Container|PrivateKey Link|Embedded'
```

Типичная КЭП ИП: `Issuer` — УЦ ФНС (`ca_fns_russia_*`), алгоритм ГОСТ Р 34.10-2012
256 бит, в `Extended Key Usage` есть «Проверка подлинности клиента» (нужна для
входа в ЛК по ГОСТ-TLS). В отчёте маскируй ФИО, ИНН, СНИЛС, ОГРНИП.

## PrivateKey Link: No

Сертификат в `uMy` есть, но не связан с ключом — сайты его «видят», а подписать
или войти нельзя.

```bash
# 1) бэкап текущего хранилища
mkdir -p ~/cryptopro-backups/$(date +%F)
certmgr -list -store uMy > ~/cryptopro-backups/$(date +%F)/uMy-before.txt

# 2) поставить сертификат из контейнера, со связью на ключ
certmgr -inst -cont '<FQCN контейнера из enum_cont>'

# 3) проверить
certmgr -list -store uMy | grep 'PrivateKey Link'
```

Если сертификатов несколько и старые мешают, удалять по одному с бэкапом:
`certmgr -delete -store uMy -thumbprint <sha1>` — только после согласия пользователя.

## certprop — автоматическая связка

`cprocsp-certprop` при вставке токена сам кладёт сертификаты в `uMy` со связью
на ключ. На NixOS — user-служба:

```bash
systemctl --user status cryptopro-certprop
systemctl --user restart cryptopro-certprop     # после смены config64.ini/CSP
```

## Считыватели: PCSC и PKCS#11

В `/etc/opt/cprocsp/config64.ini` должны быть считыватели. Для ключей, созданных
через PKCS#11 (Рутокен ЭЦП 2.0/3.0, часть ключей ФНС), CSP нужен считыватель
`cryptoki_rutoken`. Без него certprop не видел ключ, и сертификат оставался без
связи. Исправление (через `cpconfig`, перед этим — копия `config64.ini`):

```bash
cpconfig -ini '\config\KeyDevices\cryptoki_rutoken' -add long Group 1
cpconfig -ini '\config\KeyDevices\cryptoki_rutoken' -add string DLL librdrcryptoki.so
cpconfig -ini '\config\KeyDevices\cryptoki_rutoken\PNP cryptoki\Default' -add string pkcs11_dll /opt/kontur.plugin/pkcs11/librtpkcs11ecp.so
cpconfig -ini '\config\apppath' -add string librdrcryptoki.so /opt/cprocsp/lib/amd64/librdrcryptoki.so
cpconfig -ini '\config\apppath' -add string librtpkcs11ecp.so /opt/kontur.plugin/pkcs11/librtpkcs11ecp.so
```

`librtpkcs11ecp.so` — библиотека Рутокена; в примере путь указывает на
копию из Контур.Плагина. Если Контура нет — скачай с rutoken.ru и укажи свой путь.

Для Рутокен Lite (USB `0a89:0025`) достаточно обычного считывателя PCSC
(`librdrpcsc.so`) — ключ там хранится как контейнер КриптоПро.

## PIN

- Ввод PIN — только пользователем, в окне КриптоПро (нужен `libcpui` + GTK3 в
  окружении процесса, иначе окно не появится, см. known-issues).
- Не запускай без пользователя команды, которые требуют PIN: подпись
  `cryptcp -sign`, проверка ключа с открытием контейнера и т. п. Для проверки
  хватает `-verifycontext`.
- Заводской PIN пользователя Рутокена — `12345678`; если пользователь его не
  менял, подскажи сменить, но сам не меняй.
