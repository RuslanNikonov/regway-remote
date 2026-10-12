<p align="center"><img src=".github/assets/logo.png" width="420" alt="RegWay Remote"></p>

# RegWay Remote — клиент (форк RustDesk)


Клиент удалённого доступа на базе [RustDesk](https://github.com/rustdesk/rustdesk) (AGPL-3.0), который подключается **только к нашему серверу** (hbbs/hbbr + rustdesk-api на `remote.regway.group`).

## Откуда взят код

| | |
|---|---|
| Upstream | https://github.com/rustdesk/rustdesk |
| Тег | **1.5.0** (последний стабильный релиз, не prerelease; опубликован 30.09.2026) |
| Коммит | `fada664df7a294d1d1a9ca3e7cd3637069122f17` |
| Сабмодуль `libs/hbb_common` | `229b904508364c8997aad0fb5af57effac859f60` |

Зафиксировано в `UPSTREAM` и в `env.UPSTREAM_TAG` workflow. Мы **не храним** копию исходников RustDesk в репозитории: CI клонирует тег и применяет брендинг-скрипт. Это делает обновление на новый тег = смена одной строки + прогон `check-branding.sh`.

## Структура репозитория

Корень — исходники RustDesk 1.5.0 (сабмодуль `libs/hbb_common` встроен файлами) с **уже применённым** брендингом. История: коммит импорта upstream 1.5.0 + один наш коммит, поэтому `git diff HEAD~1` показывает все наши изменения. Исходный README RustDesk — `README-RustDesk.md`. Upstream-workflows RustDesk удалены (им нужны их секреты и инфраструктура), оставлен только наш.

```
.github/workflows/regway-build.yml  # сборка Windows/macOS
.github/assets/                     # логотип и social preview
regway/UPSTREAM                     # тег/коммиты upstream
regway/branding.env                 # имя, домен, ID/Relay/API; KEY подставляется из secret
regway/branding/design/             # иконки, трей, картинки установщиков
regway/scripts/apply-branding.sh    # воспроизводимый брендинг (идемпотентный)
regway/scripts/check-branding.sh    # проверки (exit 1 при нарушении)
regway/scripts/test-branding.sh     # тесты скриптов на копиях чистого клона upstream
regway/docs/                        # signing.md, heartbeat-revocation.md
regway/patches/                     # итоговый diff для ревью
```

## Как применить брендинг локально

```bash
# в этом репозитории брендинг уже применён; ключ подставить так:
# (или на чистом клоне upstream: git clone --depth 1 --branch 1.5.0 --recurse-submodules https://github.com/rustdesk/rustdesk.git rustdesk)
# реальный ключ: содержимое data/id_ed25519.pub с VPS (передавать файлом, не в чат)
KEY="$(cat /путь/к/id_ed25519.pub)" REQUIRE_REAL_KEY=1 regway/scripts/apply-branding.sh .
REQUIRE_REAL_KEY=1 regway/scripts/check-branding.sh .
```

Скрипт идемпотентен (повторный запуск с теми же значениями даёт тот же diff) и **падает**, если какой-то из патчей не нашёл исходную строку (значит upstream поменялся — нужно обновить скрипт, а не собирать «наполовину пропатченный» клиент). Применять к **чистому** клону: смена значений (например, example.com → реальный домен) на уже пропатченном дереве обновит не все места (ссылки UI), CI всегда клонирует заново. Переменные `branding.env` перекрываются окружением; `RS_PUB_KEY`/`RENDEZVOUS_SERVER` (как в CI RustDesk) тоже принимаются.

### Что меняет `apply-branding.sh`

| Что | Где (реальные пути тега 1.5.0) |
|---|---|
| Встроенный ID-сервер | `libs/hbb_common/src/config.rs`: `RENDEZVOUS_SERVERS` (был `rs-ny.rustdesk.com`), `PROD_RENDEZVOUS_SERVER` |
| Встроенный ключ | `config.rs`: `RS_PUB_KEY` (был ключ публичных серверов RustDesk) |
| Запрет смены сервера | `config.rs`: `OVERWRITE_SETTINGS` = `custom-rendezvous-server`, `relay-server`, `api-server`(пусто), `key`, `allow-auto-update=N`; `BUILTIN_SETTINGS` = `hide-server-settings=Y`, `allow-deep-link-server-settings=N` |
| Проверка обновлений | `OVERWRITE_LOCAL_SETTINGS` `enable-check-update=N`; `check_software_update()` в `src/common.rs` всегда выходит; URL `api.rustdesk.com/version/latest` в `libs/hbb_common/src/lib.rs` обнулён |
| API (rustdesk-api lejianwen) | `OVERWRITE_SETTINGS` `api-server=$API_SERVER` (`https://remote.regway.group`). `register-device` **не** задаём (иначе `get_api_server()` вернёт `""` и отключит логин, heartbeat, sysinfo, audit). Вход в учётку доступен: вкладка «Учётная запись» зависит только от `disable-account` (HARD_SETTINGS), который мы не задаём; `hide-server-settings` скрывает только раздел ID/Relay/API/Key. Фолбэк `admin.rustdesk.com` в `get_api_server_` заменён на `https://<ID-хост>` (без порта), но не достигается, т.к. API задан |
| Heartbeat → отзыв токена | `src/hbbs_http/sync.rs`: heartbeat несёт `Authorization: Bearer <access_token>` (если токен есть в LocalConfig процесса), статус читается через `post_request_with_status`; 2 подряд **HTTP 401** при отправленном токене → закрыть все входящие сеансы (канал `disconnect`) и стереть `access_token`/`user_info`. Подробно: `docs/heartbeat-revocation.md` |
| Windows: сервер из имени exe | `src/platform/windows.rs` `get_license_from_exe_name()` всегда `Err` → имена `…-host=X,key=Y,api=…,relay=….exe` и `…-licensed-<base64>.exe` игнорируются во всех местах (`get_custom_rendezvous_server`, `get_api_server_`, `get_key`, `get_rendezvous_server`, `bootstrap()`→`EXE_RENDEZVOUS_SERVER`, `ui_interface::get_license`). `get_license()` при установке не берёт Key/Host/Api из реестра; `core_main.rs` CLI `--config <строка>` отключён. Остальная логика имени (portable `RUSTDESK_APPNAME`, переименование в `<APP_NAME>.exe` при установке) не тронута |
| Текст разрыва сеанса | `src/lang/ru.rs`: «Closed manually by web console» → «Сеанс завершён администратором» (видит управляющая сторона при `disconnect` от API или отзыве токена) |
| Иконки трея | `res/tray-icon.ico` (Windows/Linux, `include_bytes!` в `src/tray.rs`), `res/mac-tray-dark-x2.png` (macOS, template), `res/mac-tray-light-x2.png` (кодом 1.5.0 не используется). `src/tray.rs`: отключена подмена на `flutter_assets/assets/icon.png`, иначе в трее был бы цветной логотип окна |
| Ссылки UI (сайт, pricing/донат, download, privacy, docs) | `flutter/lib/**` (7 файлов), `src/ui/*.tis`, `src/client.rs`, `src/lang/en.rs`, `LINK_DOCS_*` → `WEBSITE_URL` |
| Имя приложения (runtime) | `config.rs`: `APP_NAME` = `RegWayRemote` (каталоги конфигурации, имя `.exe` при установке, служба, launchd, схема `regwayremote://`); `ORG` (macOS) |
| Windows метаданные | `Cargo.toml [package.metadata.winres]`, `flutter/windows/runner/Runner.rc`, `flutter/windows/runner/main.cpp` |
| macOS метаданные | `flutter/macos/Runner/Configs/AppInfo.xcconfig` (`PRODUCT_NAME` → `RegWayRemote.app`, bundle id), `flutter/macos/Runner/Info.plist` (URL scheme, `CFBundleDisplayName`), `build.py` (путь к `.app`), `Cargo.toml [package.metadata.bundle]` |
| MSI | имя через `res/msi/preprocess.py --app-name RegWayRemote` (в CI) |
| Иконки | `res/icon.ico`, `res/tray-icon.ico`, `res/icon.png`, `res/mac-icon.png`, `res/32x32.png`, `64x64`, `128x128`, `128x128@2x`, `flutter/windows/runner/resources/app_icon.ico`, `flutter/macos/Runner/AppIcon.icns`, `flutter/assets/icon.png` (логотип в окне и трей) |
| Картинки установщиков | `res/msi/Package/Resources/WixUIBannerBmp.bmp`, `WixUIDialogBmp.bmp` (preprocess.py подхватывает сам); `res/regway/dmg-background.png` → `create-dmg --background` в CI |

Не применяется: **NSIS-картинки** — в RustDesk 1.5.0 нет NSIS-инсталлятора (Windows `.exe` = самораспаковывающийся `libs/portable` + встроенный установщик приложения, `.msi` = WiX v4). Файлы `nsis-*.bmp` лежат в `branding/design/` на случай, если появится свой NSIS. Иконки трея — из `design/tray/` (см. таблицу).

### Почему пользователь не может сменить сервер

`Config::get_option()` читает `OVERWRITE_SETTINGS` раньше пользовательского `RustDesk2.toml` (`get_or(OVERWRITE, user, DEFAULT)`), а UI (`ui_interface.rs`) не даёт сохранять ключи, присутствующие в `OVERWRITE_SETTINGS`. Это тот же механизм, что у официального «custom client» RustDesk Pro (`custom.txt` → `override-settings`), только вкомпилирован. Плюс раздел «ID/Relay сервер» скрыт (`hide-server-settings`) и deep-link не может подменить сервер. Переопределение через имя exe (`-host=…,key=…`, `-licensed-…`), реестр (миграция ≤1.2.1) и CLI `--config` отключено патчем (см. таблицу).

### Проверка «нет серверов RustDesk»

`regway/scripts/check-branding.sh` ищет `rustdesk.com|rs-ny|rs-sg|rs-cn` в `src`, `libs/hbb_common/src`, `flutter/lib`. Допустимые остатки (allowlist):
* `src/common.rs:1031` — комментарий;
* `src/common.rs:1175` — `is_public()`: **детектор** «это публичный сервер RustDesk?», сам никуда не подключается;
* `src/common.rs:3xxx`, `libs/hbb_common/src/websocket.rs:48x–52x`, `socket_client.rs:31x–32x` — `#[cfg(test)]` юнит-тесты.

Вне этих каталогов (`res/`, `flatpak/`, `fastlane/`, `Cargo.toml` deps `rustdesk-org/*` на GitHub, драйверы `github.com/rustdesk/...` в CI) — метаданные пакетов и источники зависимостей сборки, не код подключения.

## CI: `.github/workflows/regway-build.yml`

Основан на официальном `flutter-build.yml` тега 1.5.0 (те же Flutter 3.24.5 + кастомный engine RustDesk для Windows, Rust 1.75/1.81, vcpkg `9e593bb…`, flutter_rust_bridge 1.80.1). Workflow делает checkout этого репозитория в `./rustdesk` и повторно запускает `regway/scripts/apply-branding.sh`, чтобы подставить ключ из secret.

Запуск: вручную (`workflow_dispatch`) или пушем тега `v*`. Джобы: `generate-bridge` → `build-windows-x64` (windows-2022) + `build-macos` (macos-15-intel x86_64, macos-14 arm64). Результат — artifacts джоб (релиз на GitHub не публикуется; добавить `softprops/action-gh-release`, когда решим, где раздаём).

### Артефакты (VERSION = версия upstream, 1.5.0)

| Платформа | Файл |
|---|---|
| Windows x64, установщик/портативный | `RegWayRemote-1.5.0-x86_64.exe` |
| Windows x64, MSI | `RegWayRemote-1.5.0-x86_64.msi` |
| macOS Intel | `RegWayRemote-1.5.0-x86_64.dmg` |
| macOS Apple Silicon | `RegWayRemote-1.5.0-aarch64.dmg` |
| + `SHA256SUMS-windows.txt`, `SHA256SUMS-macos-<arch>.txt` | |

Имена artifacts в Actions: `RegWayRemote-windows-x86_64`, `RegWayRemote-macos-x86_64`, `RegWayRemote-macos-aarch64`.

### Secrets

| Secret | Обязателен | Назначение |
|---|---|---|
| `RS_PUB_KEY` | да для релиза (`REQUIRE_REAL_KEY=1` при push тега и по умолчанию в dispatch) | содержимое `data/id_ed25519.pub` |

При `REQUIRE_REAL_KEY=1` `apply-branding.sh` падает, если: KEY не 44-символьный base64 ed25519; хосты не **ровно** `remote.regway.group` (ID), `remote.regway.group:21117` (relay), `https://remote.regway.group` (API) — хост зашит в скрипте (`REGWAY_HOST`), а не берётся из окружения; `WEBSITE_URL`/`DOMAIN` содержат example.*. `check-branding.sh` при `REQUIRE_REAL_KEY=1` дополнительно проверяет эти значения в `config.rs` и что ключ не плейсхолдер-строка. Тесты: `scripts/test-branding.sh` (15 случаев). `WEBSITE_URL` проверяется тоже: ссылки «Сайт/Скачать/Конфиденциальность» на example.com в релизе — дефект. Домен прописан: `remote.regway.group` (ID), `remote.regway.group:21117` (relay), `https://remote.regway.group` (API и WEBSITE_URL).
| `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_SIGNING_ENDPOINT`, `AZURE_SIGNING_ACCOUNT`, `AZURE_CERT_PROFILE` | нет | подпись Windows через Azure Artifact Signing (бывш. Trusted Signing). Без них шаги пропускаются |
| `MACOS_P12_BASE64`, `MACOS_P12_PASSWORD`, `MACOS_CODESIGN_IDENTITY` | нет | Developer ID Application (.p12) для `codesign` |
| `APPLE_API_KEY_P8_BASE64`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID` | нет | App Store Connect API key для `notarytool` |

Без secrets сборка проходит и даёт **неподписанные** файлы. Как добавить: Settings → Secrets and variables → Actions, или `gh secret set RS_PUB_KEY < id_ed25519.pub`. Локально секреты держим только в файлах с `chmod 600` (каталог `secrets/` в `.gitignore`).

Отличия от upstream-workflow: убраны Windows arm64, sciter, Linux/Android/iOS, SBOM, их сервис подписи `SIGN_BASE_URL`, публикация в их релиз `nightly`, сборка `RustDeskTempTopMostWindow` (нужна только для «режима конфиденциальности» в варианте с внедрением в процесс; без неё сборка проходит, privacy mode 2 по-прежнему работает через виртуальный дисплей — проверить на QA). Нотаризация — `xcrun notarytool` вместо `rcodesign`.

## Лицензия AGPL-3.0 — что обязательно

RustDesk распространяется под **GNU AGPL-3.0** (`rustdesk/LICENCE`). Наш клиент — производная работа, поэтому:

1. **Публикуем исходники нашей версии** (форк + `apply-branding.sh` + workflow) под AGPL-3.0 и даём ссылку на них всем, кто получает бинарники (страница загрузки, «О программе»). AGPL §13 дополнительно требует предлагать исходники пользователям, взаимодействующим с программой по сети, — для клиента и для нашего hbbs/hbbr (тоже AGPL) держим публичный репозиторий.
2. **Сохраняем лицензию и копирайты**: файл `LICENCE`, заголовки, `Copyright © Purslane Tech Pte. Ltd.` в метаданных заменены на «Based on RustDesk … AGPL-3.0; modifications (c) RegWay» — оригинальное авторство упомянуто.
3. **Указываем RustDesk** как основу (README, «О программе», сайт) и отмечаем, что файлы изменены (AGPL §5a — «prominent notices», это делают патчи скрипта и этот README).
4. Не добавляем ограничений сверх AGPL; не вшиваем проприетарных компонентов, которые нельзя распространять под AGPL.
5. Товарный знак «RustDesk» и их логотип не используем как своё название — поэтому и брендинг.

Ключ сервера (`RS_PUB_KEY`) — публичный, его наличие в исходниках не секрет. Приватный `id_ed25519` в репозиторий не попадает никогда.
