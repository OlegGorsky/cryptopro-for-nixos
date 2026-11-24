# Проверенные версии и зависимости

Проверено на: NixOS `26.05pre` (unstable), GNOME, x86_64.

| Компонент | Версия | Откуда | Куда ставится |
|---|---|---|---|
| КриптоПро CSP | 5.0.13003 (KC1), архив `linux-amd64_deb.tgz` | cryptopro.ru, личный кабинет | `/opt/cprocsp`, `/etc/opt/cprocsp`, `/var/opt/cprocsp` |
| ЭЦП Browser plug-in (CAdES) | 2.0.15700 (раньше 2.0.15500, 2.0.15003) | cryptopro.ru, `cades-linux-amd64.tar.gz` | `/opt/cprocsp/bin/amd64/nmcades`, `/opt/cprocsp/lib/amd64/libnpcades.so*` |
| Расширение CAdES (новое, MV3) | 1.3.17 | Chrome Web Store, ID `pfhgbfnnjiafkhfdkmpiflachepdcjod` | профиль браузера |
| Расширение CAdES (старое, MV2) | 1.2.13 | ID `iifchhfnnmpdbibifmljnfjhpififfog` | нужно только старым сайтам |
| Google Chrome | 147 | nixpkgs `google-chrome` | `/opt/google/chrome` |
| Chromium-Gost | 150.0.7871.224 проверен; на 24.11.2026 последняя — 156.0.8078.108 | github.com/deemru/chromium-gost/releases, `*-linux-amd64.deb` | `/opt/chromium-gost` |
| Контур.Плагин | из пакета Контура | kontur.ru | `/opt/kontur.plugin` (+ `pkcs11/librtpkcs11ecp.so`) |
| ifd-rutokens | 1.0.4 | входит в архив CSP | `/opt/aktivco/ifd-rutokens` |
| pcsc-lite / ccid | из nixpkgs | `services.pcscd` | системная служба |
| Рутокен | Рутокен Lite (USB `0a89:0025`), считыватель `rutoken_lt_*` | — | — |
| Сертификат | КЭП от УЦ ФНС (`ca_fns_russia_2025_01`), ГОСТ Р 34.10-2012 256 | ФНС | на токене |
| Корень Минцифры | `Russian Trusted Root CA`, до 27.02.2032 | gosuslugi.ru/crt | `certs/`, системное хранилище, NSS |

## Пакеты CSP, которые реально нужны

Обязательные: `lsb-cprocsp-base`, `lsb-cprocsp-rdr-64`, `lsb-cprocsp-capilite-64`,
`lsb-cprocsp-kc1-64`, `lsb-cprocsp-pkcs11-64`, `lsb-cprocsp-ca-certs`,
`cprocsp-curl-64`, `cprocsp-rdr-pcsc-64`, `cprocsp-rdr-rutoken-64`,
`cprocsp-rdr-cryptoki-64`, `cprocsp-rdr-gui-gtk-64`, `cprocsp-cptools-gtk-64`,
`cprocsp-certprop-64`.

Желательные: `ifd-rutokens`, `cprocsp-legacy-64`.

CAdES: `cprocsp-pki-cades-64`, `cprocsp-pki-plugin-64`.

Остальное из архива (nginx, apache, stunnel, jacarta, esmart и т. д.) не нужно.

## Библиотеки nix-ld

Для CSP и окна КриптоПро: `alsa-lib at-spi2-core cairo curl dbus expat fontconfig
freetype gcc.cc.lib gdk-pixbuf glib gtk3 libdrm libGL libxkbcommon libxml2 nspr nss
openssl pango pcsclite stdenv.cc.cc.lib zlib`.

Дополнительно для Chromium-Gost: `atk at-spi2-atk cups libglvnd mesa libgbm libx11
libxcb libxcomposite libxdamage libxext libxfixes libxrandr libxshmfence`.

С этим набором `ldd /opt/chromium-gost/chrome` не показывает `not found`.

## Как проверить версии на машине

```bash
csptest -keyset -verifycontext | head -1        # версия CSP
cpconfig -license -view                         # лицензия
ls /opt/cprocsp/lib/amd64/libnpcades.so.*       # CAdES
chromium-gost --version
google-chrome-stable --version
```
