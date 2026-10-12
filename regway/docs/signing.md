# Подпись клиента RegWay Remote

Проверено по источникам на 12.10.2026 (ссылки у каждого пункта). CI-шаги — `.github/workflows/regway-build.yml`, все выполняются **только при наличии secrets**.

## Windows

### Что нужно
* **Сертификат подписи кода** (Authenticode) от публичного CA — OV (организация) или EV.
* **С 1 июня 2023** закрытый ключ любого публичного code-signing сертификата (OV и EV) обязан генерироваться и храниться в аппаратном модуле (HSM/USB-токен, FIPS 140-2 L2 / CC EAL4+) или в облачном HSM/сервисе подписи. «Файл .pfx на диске», как раньше, больше не выдают — в CI это значит облачная подпись (Azure Key Vault/Managed HSM, сервисы CA вроде DigiCert KeyLocker/SSL.com eSigner, SignPath) или self-hosted runner с токеном.
  * CA/B Forum Code Signing BR §6.2.7.4.2: https://cabforum.org/uploads/Baseline-Requirements-for-the-Issuance-and-Management-of-Code-Signing.v3.4.pdf
* **EV больше не даёт мгновенной репутации SmartScreen.** Microsoft перестала особо признавать EV code signing (февраль 2024, OID удалены в августе 2024); OV и EV копят репутацию одинаково, подписанный файл без репутации всё равно показывает предупреждение, но с именем издателя. Платить за EV ради SmartScreen смысла нет.
  * https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation
  * https://learn.microsoft.com/en-us/security/trusted-root/program-requirements (§3.D.3)
* **Репутация SmartScreen** накапливается по сертификату/файлу через число «чистых» скачиваний и запусков; на старте пользователи увидят «Windows защитила ваш компьютер → Подробнее → Выполнить в любом случае». Для программы удалённого доступа ещё вероятны ложные срабатывания AV — стоит заранее отправлять сборки в Microsoft Security Intelligence (submission portal) как false positive.
* **signtool** (Windows SDK): `signtool sign /fd SHA256 /tr <RFC3161 TSA> /td SHA256 /dlib <dlib облачного провайдера> /dmdf metadata.json file.exe`; проверка `signtool verify /pa /v file.exe`. Всегда с меткой времени (`/tr`) — иначе подпись «умрёт» вместе с сертификатом.

### Варианты
| Вариант | Цена (если нашёл в источнике) | Ограничения |
|---|---|---|
| **Azure Artifact Signing** (бывш. Trusted Signing, переименован при GA, янв. 2026) | Basic **$9.99/мес** (5 000 подписей, далее $0.005/подпись), Premium $99.99/мес — https://learn.microsoft.com/en-us/azure/artifact-signing/how-to-change-sku | Public Trust только для организаций из США, Канады, ЕС, UK, Австралии, Новой Зеландии, Японии, Ю. Кореи, Сингапура, Швейцарии, Норвегии, Израиля и частных лиц из США/Канады (https://learn.microsoft.com/en-us/azure/trusted-signing/quickstart). Нужна платная подписка Azure (не trial) — https://learn.microsoft.com/en-us/azure/artifact-signing/faq. GitHub Action: `azure/artifact-signing-action` (старое имя `azure/trusted-signing-action` перестало резолвиться — https://github.com/Azure/artifact-signing-action/discussions/109). **Используется в нашем workflow.** |
| **SignPath Foundation** (бесплатно для OSS) | бесплатно — https://signpath.org/ | Сертификат выдаётся на SignPath Foundation (издатель — они, не мы); только OSI-лицензия без коммерческого dual-licensing, без проприетарных компонентов, проект уже выпущен и активно поддерживается, публичный репозиторий, проверяемая сборка из исходников, code signing policy на сайте, MFA — https://signpath.org/terms.html. «Sign your own projects only»: подписывать можно только собственный код; форк RustDesk формально подходит под AGPL, но решение — за SignPath. |
| OV/EV у CA (DigiCert, Sectigo, SSL.com, GlobalSign, Certum…) + облачный HSM/токен | цены в источниках не проверял | Валидация организации; ключ на токене (физический USB → нужен self-hosted runner) или облачный сервис CA. Для юрлица в РФ доступность у западных CA нужно проверить отдельно. |

### Secrets для workflow (Artifact Signing)
`AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` (App Registration с ролью «Artifact Signing Certificate Profile Signer»), `AZURE_SIGNING_ENDPOINT` (например `https://eus.codesigning.azure.net/`), `AZURE_SIGNING_ACCOUNT`, `AZURE_CERT_PROFILE`. Подписываются сначала `exe/dll` в папке сборки (до упаковки), затем итоговые `.exe` и `.msi`.

## macOS

### Что нужно
* **Apple Developer Program** — **99 USD в год** (в местной валюте, где доступна). Нужен для Developer ID сертификатов и нотаризации. https://developer.apple.com/programs/whats-included/ , https://developer.apple.com/help/account/membership/program-enrollment
  Для организации — регистрация как Organization (нужен D-U-N-S номер); иначе издателем будет физлицо.
* **Сертификат «Developer ID Application»** (для распространения вне App Store), выпускает Account Holder: https://developer.apple.com/developer-id/ . Экспортировать в `.p12` → base64 → secret `MACOS_P12_BASE64` (+ `MACOS_P12_PASSWORD`, `MACOS_CODESIGN_IDENTITY` = `Developer ID Application: <Org> (<TEAMID>)`). Сам .dmg подписывается тем же сертификатом. («Developer ID Installer» нужен только для .pkg.)
* **Hardened Runtime** обязателен для нотаризации: `codesign --options runtime --timestamp`. В RustDesk это делает `.github/scripts/sign-macos-app.sh` (подписывает Frameworks, `service`, затем `.app` с `flutter/macos/Runner/Release.entitlements`).
* **Entitlements** (`Release.entitlements` RustDesk): `app-sandbox=false`, `cs.allow-jit=true`, `device.audio-input=true` (микрофон при hardened runtime), `network.client=true`.
  **Запись экрана и Универсальный доступ (Accessibility) не являются entitlements** для Developer ID-приложений — это разрешения TCC, которые выдаёт пользователь в «Системные настройки → Конфиденциальность и безопасность» (инструкция Дизайнера `design/guide/macos-permissions.md`). Привязка разрешений идёт к подписи и bundle id, поэтому: стабильный bundle id (`com.regway.remote`) и одна и та же Team ID между версиями — иначе пользователям придётся выдавать разрешения заново. Usage-строки (`NSMicrophoneUsageDescription` и т.п.) задаются в `Info.plist`.
* **Нотаризация** — `xcrun notarytool submit <file> --wait` с App Store Connect API key (`--key AuthKey.p8 --key-id --issuer`) или Apple ID + app-specific password. https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
* **Stapler**: `xcrun stapler staple RegWayRemote-<ver>-<arch>.dmg` и `xcrun stapler validate` — тикет вшивается, Gatekeeper не нужен онлайн. Проверка: `spctl -a -t open --context context:primary-signature -v <dmg>`.
* Secrets для workflow: `APPLE_API_KEY_P8_BASE64`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID` (App Store Connect → Users and Access → Integrations → Keys, роль Developer).

Без подписи: macOS Sonoma/Sequoia не даёт открыть неподписанный .app двойным кликом; в Sequoia (15) обход только через «Системные настройки → Конфиденциальность и безопасность → Всё равно открыть» или `xattr -dr com.apple.quarantine`. Для пользователей это неприемлемо — для релиза macOS подпись+нотаризация фактически обязательны.
