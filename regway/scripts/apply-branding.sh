#!/usr/bin/env bash
# Применяет брендинг RegWay Remote к чистому клону rustdesk (тег из ../UPSTREAM).
# Использование: scripts/apply-branding.sh [RUSTDESK_DIR] [DESIGN_DIR]
#   RUSTDESK_DIR по умолчанию ./rustdesk, DESIGN_DIR по умолчанию ./branding/design (копия ../design, scripts/sync-design.sh)
# Переменные из branding.env можно переопределить окружением (CI: KEY=${{ secrets.RS_PUB_KEY }}).
# REQUIRE_REAL_KEY=1 — упасть, если KEY остался плейсхолдером (включено в CI для релизов).
# Скрипт идемпотентен: повторный запуск на уже пропатченном дереве ничего не ломает.
# Каждая замена проверяется: если в новом теге upstream строка изменилась — скрипт падает,
# а не тихо собирает клиент со старыми серверами RustDesk.
set -euo pipefail
# Windows GitHub runners use cp1252 for Python stdout; keep UTF-8 for Cyrillic logs.
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hbbs-key.sh
source "$HERE/scripts/hbbs-key.sh"
RD="$(cd "${1:-$HERE/rustdesk}" && pwd)"
DESIGN="$(cd "${2:-$HERE/branding/design}" && pwd)"

# окружение имеет приоритет над branding.env
_env_snapshot="$(export -p)"
set -a; source "$HERE/branding.env"; set +a
eval "$_env_snapshot"
[ -n "${RS_PUB_KEY:-}" ] && KEY="$RS_PUB_KEY"
[ -n "${RENDEZVOUS_SERVER:-}" ] && ID_SERVER="$RENDEZVOUS_SERVER"

[[ "$APP_NAME" =~ ^[A-Za-z][A-Za-z0-9]*$ ]] || { echo "APP_NAME должен быть [A-Za-z0-9] без пробелов" >&2; exit 1; }
if [[ ! "$KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
  if [ "${REQUIRE_REAL_KEY:-0}" = 1 ]; then echo "KEY не похож на ed25519 pub key hbbs (44 символа base64)" >&2; exit 1; fi
  echo "WARN: KEY — плейсхолдер ('$KEY'). Клиент не подключится к серверу, пока не задан реальный ключ." >&2
fi
ID_HOST="${ID_SERVER%%:*}"
# Единственный допустимый хост релизной сборки (не берётся из branding.env/окружения намеренно)
REGWAY_HOST=remote.regway.group
# Защита от сборки с плейсхолдерами: при REQUIRE_REAL_KEY=1 запрещены example.* в адресах и сайте
if [ "${REQUIRE_REAL_KEY:-0}" = 1 ]; then
  for v in ID_SERVER RELAY_SERVER API_SERVER WEBSITE_URL HELP_URL DOMAIN; do
    if printf '%s' "${!v:-}" | grep -qiE '(^|[./@])example\.(com|net|org)([:/]|$)'; then
      echo "ОШИБКА: $v='${!v}' — плейсхолдер example.*; задайте реальный домен (REQUIRE_REAL_KEY=1)" >&2; exit 1
    fi
  done
  # Хост зафиксирован: релизная сборка только для нашего сервера
  H="$REGWAY_HOST"
  [ "$ID_SERVER" = "$H" ]             || { echo "ОШИБКА: ID_SERVER='$ID_SERVER', ожидается ровно '$H'" >&2; exit 1; }
  [ "$RELAY_SERVER" = "$H:21117" ]    || { echo "ОШИБКА: RELAY_SERVER='$RELAY_SERVER', ожидается ровно '$H:21117'" >&2; exit 1; }
  [ "$API_SERVER" = "https://$H" ]    || { echo "ОШИБКА: API_SERVER='$API_SERVER', ожидается ровно 'https://$H'" >&2; exit 1; }
fi

# Public hbbs key check. Never print the full key: sha256 + first/last 4 chars.
echo "hbbs KEY fingerprint: $(hbbs_key_fingerprint "$KEY")"
echo "hbbs expected fingerprint: $(hbbs_key_fingerprint "$EXPECTED_HBBS_PUB_KEY")"
if [ "${REQUIRE_REAL_KEY:-0}" = 1 ]; then
  if [ "$KEY" != "$EXPECTED_HBBS_PUB_KEY" ]; then
    echo "ОШИБКА: RS_PUB_KEY не совпадает с ожидаемым публичным ключом hbbs." >&2
    echo "  secret:   $(hbbs_key_fingerprint "$KEY")" >&2
    echo "  expected: $(hbbs_key_fingerprint "$EXPECTED_HBBS_PUB_KEY")" >&2
    echo "Секрет в GitHub Actions нельзя поменять из этого агента; обновите RS_PUB_KEY вручную." >&2
    exit 1
  fi
  echo "OK   RS_PUB_KEY matches expected hbbs public key"
fi

export RD APP_NAME APP_DISPLAY_NAME ORG BUNDLE_ID COMPANY ID_SERVER ID_HOST RELAY_SERVER API_SERVER KEY WEBSITE_URL HELP_URL DOMAIN
python3 - <<'PY'
import os, re, sys, pathlib
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass
E = os.environ
RD = pathlib.Path(E["RD"])
errors = []

def sub(rel, pattern, repl, *, regex=False, required=True, count=0, skip_if=None):
    p = RD / rel
    s = p.read_text(encoding="utf-8")
    if skip_if and skip_if in s:  # вставка уже сделана (идемпотентность для вставок, где pattern остаётся)
        return 0
    if regex:
        new, n = re.subn(pattern, repl, s, count=count, flags=re.M)
    else:
        n = s.count(pattern); new = s.replace(pattern, repl) if n else s
    if n == 0:
        # уже применено? (идемпотентность): проверяем, что целевое значение присутствует
        if required and (regex or repl not in s):
            errors.append(f"{rel}: не найдено: {pattern!r}")
        return 0
    p.write_text(new, encoding="utf-8")
    return n

q = lambda v: v.replace("\\", "\\\\").replace('"', '\\"')
APP, DISP, KEY = E["APP_NAME"], E["APP_DISPLAY_NAME"], E["KEY"]
ID, RELAY, API, HOST, WEB = E["ID_SERVER"], E["RELAY_SERVER"], E["API_SERVER"], E["ID_HOST"], E["WEBSITE_URL"]
HELP = E.get("HELP_URL") or (WEB.rstrip("/") + "/help/")
if not HELP.endswith("/"):
    HELP += "/"

# ---------- 1. Встроенные сервер/ключ/имя (libs/hbb_common/src/config.rs) ----------
# Host is locked in two places:
#   RENDEZVOUS_SERVERS + PROD_RENDEZVOUS_SERVER — compiled default (used when
#     custom-rendezvous-server is empty; get_custom_rendezvous_server falls back here).
#   OVERWRITE_SETTINGS["custom-rendezvous-server"] — user cannot override via RustDesk2.toml.
# API is locked the same way as host/key: OVERWRITE_SETTINGS["api-server"] and HARD_SETTINGS.
cfg = "libs/hbb_common/src/config.rs"
sub(cfg, r'pub const RENDEZVOUS_SERVERS: &\[&str\] = &\[[^\]]*\];',
    f'pub const RENDEZVOUS_SERVERS: &[&str] = &["{q(ID)}"];', regex=True)
sub(cfg, r'pub const RS_PUB_KEY: &str = "[^"]*";', f'pub const RS_PUB_KEY: &str = "{q(KEY)}";', regex=True)
sub(cfg, r'pub static ref PROD_RENDEZVOUS_SERVER: RwLock<String> = RwLock::new\("[^"]*"\.to_owned\(\)\);',
    f'pub static ref PROD_RENDEZVOUS_SERVER: RwLock<String> = RwLock::new("{q(ID)}".to_owned());', regex=True)
sub(cfg, r'pub static ref APP_NAME: RwLock<String> = RwLock::new\("[^"]*"\.to_owned\(\)\);',
    f'pub static ref APP_NAME: RwLock<String> = RwLock::new("{q(APP)}".to_owned());', regex=True)
sub(cfg, r'pub static ref ORG: RwLock<String> = RwLock::new\("[^"]*"\.to_owned\(\)\);',
    f'pub static ref ORG: RwLock<String> = RwLock::new("{q(E["ORG"])}".to_owned());', regex=True)
# OVERWRITE_* имеют приоритет над конфигом пользователя (Config::get_option -> get_or):
# пользователь не может переопределить сервер/ключ/релей/API, даже правкой RustDesk2.toml.
def map_init(pairs):
    items = ", ".join(f'("{q(k)}".to_owned(), "{q(v)}".to_owned())' for k, v in pairs)
    return f"RwLock::new(HashMap::from([{items}]))"
ow = [("custom-rendezvous-server", ID), ("relay-server", RELAY), ("api-server", API), ("key", KEY),
      ("allow-auto-update", "N")]
sub(cfg, r'pub static ref OVERWRITE_SETTINGS: RwLock<HashMap<String, String>> = [^\n]*$',
    f'pub static ref OVERWRITE_SETTINGS: RwLock<HashMap<String, String>> = {map_init(ow)}; // RegWay', regex=True)
sub(cfg, r'pub static ref HARD_SETTINGS: RwLock<HashMap<String, String>> = (?:Default::default\(\)|[^\n]*)$',
    f'pub static ref HARD_SETTINGS: RwLock<HashMap<String, String>> = {map_init([("api-server", API)])}; // RegWay', regex=True)
sub(cfg, r'pub static ref OVERWRITE_LOCAL_SETTINGS: RwLock<HashMap<String, String>> = [^\n]*$',
    'pub static ref OVERWRITE_LOCAL_SETTINGS: RwLock<HashMap<String, String>> = '
    + map_init([("enable-check-update", "N")]) + '; // RegWay', regex=True)
# BUILTIN: скрыть раздел «ID/Relay сервер», не принимать сервер из deep-link
sub(cfg, r'pub static ref BUILTIN_SETTINGS: RwLock<HashMap<String, String>> = [^\n]*$',
    'pub static ref BUILTIN_SETTINGS: RwLock<HashMap<String, String>> = '
    + map_init([("hide-server-settings", "Y"), ("allow-deep-link-server-settings", "N")]) + '; // RegWay', regex=True)
sub(cfg, r'pub const LINK_DOCS_HOME: &str = "[^"]*";', f'pub const LINK_DOCS_HOME: &str = "{q(HELP)}";', regex=True)
sub(cfg, r'pub const LINK_DOCS_X11_REQUIRED: &str = "[^"]*";', f'pub const LINK_DOCS_X11_REQUIRED: &str = "{q(HELP)}";', regex=True)

# ---------- 2. Проверка обновлений / API RustDesk ----------
sub("libs/hbb_common/src/lib.rs", 'const URL: &str = "https://api.rustdesk.com/version/latest";',
    'const URL: &str = ""; // RegWay: upstream version check disabled')
# do_check_software_update/updater: жёстко выходим (и так не вызывается для custom client)
sub("src/common.rs", "pub fn check_software_update() {\n    if is_custom_client() {",
    "pub fn check_software_update() {\n    if true || is_custom_client() { // RegWay")
sub("src/common.rs",
    r'"(?:https://admin\.rustdesk\.com|https?://[^"]+:21114|https://' + re.escape(HOST) + r')"\.to_owned\(\)',
    f'"https://{q(HOST)}".to_owned()', regex=True)
_s0_old = (
    "    if !s0.is_empty() {\n"
    "        let s = crate::increase_port(&s0, -2);\n"
    "        if s == s0 {\n"
    '            return format!("http://{}:{}", s, config::RENDEZVOUS_PORT - 2);\n'
    "        } else {\n"
    '            return format!("http://{}", s);\n'
    "        }\n"
    "    }"
)
_s0_new = (
    "    if !s0.is_empty() {\n"
    "        // Port 21114 is not exposed; API is only https://" + HOST + " (nginx).\n"
    "        let host = s0.split(':').next().unwrap_or(s0.as_str());\n"
    f'        if host.eq_ignore_ascii_case("{q(HOST)}") {{\n'
    f'            return "https://{q(HOST)}".to_owned();\n'
    "        }\n"
    "        let s = crate::increase_port(&s0, -2);\n"
    "        if s == s0 {\n"
    '            return format!("http://{}:{}", s, config::RENDEZVOUS_PORT - 2);\n'
    "        } else {\n"
    '            return format!("http://{}", s);\n'
    "        }\n"
    "    }"
)
sub("src/common.rs", _s0_old, _s0_new)
# Don't leave a literal ":21114" in built sources; same port as RENDEZVOUS_PORT - 2.
sub("src/common.rs",
    '    if res.starts_with("https")\n        && res.ends_with(":21114")\n        && get_builtin_option(keys::OPTION_ALLOW_HTTPS_21114) != "Y"\n    {\n        return res.replace(":21114", "");\n    }',
    '    let api_http_port = config::RENDEZVOUS_PORT - 2;\n    if res.starts_with("https")\n        && res.ends_with(&format!(":{api_http_port}"))\n        && get_builtin_option(keys::OPTION_ALLOW_HTTPS_21114) != "Y"\n    {\n        return res.replace(&format!(":{api_http_port}"), "");\n    }')
# Unit-test fixtures also used :21114; rewrite so check-branding can ban the literal.
sub("src/common.rs", "https://admin.example.com:21114/", "https://admin.example.com:8443/")
sub("src/common.rs", "https://[2001:db8::1]:21114/", "https://[2001:db8::1]:8443/")

# ---------- 2b. Windows: запрет сервера/ключа из имени exe (custom_server.rs) ----------
# get_license_from_exe_name() разбирает имя exe ("...-host=X,key=Y,api=Z,relay=R.exe" и
# "-licensed-<base64>") и перекрывает сервер/ключ/API в common.rs (get_custom_rendezvous_server,
# get_api_server_, get_key, get_rendezvous_server), ui_interface::get_license, bootstrap()
# (EXE_RENDEZVOUS_SERVER) и install_me (get_license). Отключаем в одном месте — функция всегда Err,
# все вызовы уже обрабатывают Err как "лицензии в имени нет". PORTABLE_APPNAME (имя приложения
# для портативного режима) и прочая логика имени exe не затрагиваются.
win = "src/platform/windows.rs"
sub(win, "        exe = portable_exe;\n    }\n    get_custom_server_from_string(&exe)\n}",
    "        exe = portable_exe;\n    }\n    // RegWay: server/key override via exe name is disabled\n"
    "    let _ = exe;\n"
    "    hbb_common::bail!(\"exe-name server override disabled\")\n}")
# legacy fallback из реестра (Key/Host/Api, миграция <=1.2.1) при установке
sub(win, "    if lic.key.is_empty() || lic.host.is_empty() {\n        return None;",
    "    if true || lic.key.is_empty() || lic.host.is_empty() { // RegWay: no registry/exe-name override\n        return None;")
# CLI `--config <exe-name-string>` (запись сервера из строки имени)
sub("src/core_main.rs", '            if args.len() == 2 && !args[0].contains("host=") {\n                if crate::platform::is_installed() && is_root() {\n                    // encrypted string',
    '            if false && args.len() == 2 { // RegWay: --config <server string> disabled\n                if crate::platform::is_installed() && is_root() {\n                    // encrypted string')

# ---------- 2c. Трей: иконки дизайнера из res/, а не логотип из flutter assets ----------
# src/tray.rs: load_icon_from_asset() (flutter_assets/assets/icon.png) имеет приоритет над
# include_bytes!(res/tray-icon.ico | res/mac-tray-dark-x2.png). Мы кладём icon.png как логотип окна,
# поэтому выключаем подмену, чтобы в трее была специальная иконка.
sub("src/tray.rs", "let image = load_icon_from_asset()\n            .unwrap_or(",
    "let image = load_icon_from_asset()\n            .filter(|_| false) // RegWay: use res/ tray icons\n            .unwrap_or(")

# ---------- 2d. Heartbeat: Bearer-токен + реакция на явный HTTP 401 (src/hbbs_http/sync.rs) ----------
# Upstream шлёт heartbeat без токена и игнорирует HTTP-статус. Патч:
#  * если в LocalConfig этого процесса есть access_token — добавляет "Authorization: Bearer";
#  * читает статус (post_request_with_status); ТОЛЬКО HTTP 401 при отправленном токене считается
#    отзывом; после REGWAY_401_THRESHOLD подряд (2xx сбрасывает счётчик, 5xx/таймаут/TLS — нейтральны)
#    закрываются все входящие сеансы (тот же канал, что и {"disconnect":[...]}) и токен стирается.
hb = "src/hbbs_http/sync.rs"
sub(hb, "const TIME_CONN: Duration = Duration::from_secs(3);",
    "const TIME_CONN: Duration = Duration::from_secs(3);\n"
    "// RegWay: consecutive explicit HTTP 401 replies (token sent) before revoking\n"
    "const REGWAY_401_THRESHOLD: u32 = 2;", skip_if="REGWAY_401_THRESHOLD")
sub(hb, "    let mut sysinfo_ver = \"\".to_owned();\n    loop {",
    "    let mut sysinfo_ver = \"\".to_owned();\n    let mut regway_401_count: u32 = 0;\n    loop {", skip_if="let mut regway_401_count")
sub(hb, """                let response = crate::post_request(url.clone(), v.to_string(), "").await;
                if let Err(err) = &response {
                    hbb_common::throttled_log!(API_LOG_INTERVAL, warn, "Heartbeat failed: {err:?}");
                }
                if let Ok(s) = response {""",
"""                // RegWay: send the account token and act on an explicit 401 only
                let token = LocalConfig::get_option("access_token");
                let header = if token.is_empty() {
                    "".to_owned()
                } else {
                    format!("Authorization: Bearer {}", token)
                };
                let response = crate::post_request_with_status(url.clone(), v.to_string(), &header).await;
                if let Err(err) = &response {
                    hbb_common::throttled_log!(API_LOG_INTERVAL, warn, "Heartbeat failed: {err:?}");
                }
                let response = match response {
                    Ok((401, _)) if !token.is_empty() => {
                        regway_401_count += 1;
                        log::warn!("Heartbeat: HTTP 401 ({}/{})", regway_401_count, REGWAY_401_THRESHOLD);
                        if regway_401_count >= REGWAY_401_THRESHOLD {
                            regway_401_count = 0;
                            regway_revoke_sessions(&token);
                        }
                        continue;
                    }
                    Ok((status, s)) => {
                        if (200..300).contains(&status) {
                            regway_401_count = 0;
                        }
                        Ok(s)
                    }
                    Err(e) => Err(e),
                };
                if let Ok(s) = response {""")
sub(hb, "fn heartbeat_url() -> String {",
"""// RegWay: the API explicitly rejected our token: close all incoming sessions, forget the token.
#[cfg(not(any(target_os = "ios")))]
fn regway_revoke_sessions(token: &str) {
    let conns = Connection::alive_conns();
    log::warn!("API rejected access token: closing {} incoming session(s)", conns.len());
    if !conns.is_empty() {
        SENDER.lock().unwrap().send(conns).ok();
    }
    if LocalConfig::get_option("access_token") == token {
        LocalConfig::set_option("access_token".to_owned(), "".to_owned());
        LocalConfig::set_option("user_info".to_owned(), "".to_owned());
    }
}

fn heartbeat_url() -> String {""", skip_if="fn regway_revoke_sessions")

# ---------- 2e. Русская причина закрытия сеанса (показывается управляющей стороне) ----------
sub("src/lang/ru.rs", r'^(\s*\("Closed manually by web console", )"[^"]*"\),',
    r'\1"Сеанс завершён администратором"),', regex=True)

# ---------- 3. Ссылки в UI (сайт/цены/скачать/приватность/доки) ----------
url_re = r'https?://(?:www\.)?rustdesk\.com[^\'"\s)]*'
for rel in ["flutter/lib/common.dart", "flutter/lib/desktop/pages/desktop_setting_page.dart",
            "flutter/lib/desktop/pages/connection_page.dart", "flutter/lib/desktop/pages/desktop_home_page.dart",
            "flutter/lib/desktop/pages/install_page.dart", "flutter/lib/mobile/pages/settings_page.dart",
            "flutter/lib/mobile/pages/connection_page.dart", "src/ui/index.tis", "src/ui/install.tis",
            "src/client.rs", "src/lang/en.rs"]:
    sub(rel, url_re, WEB, regex=True, required=False)
sub("flutter/lib/mobile/pages/settings_page.dart", "Text('rustdesk.com',", f"Text('{E['DOMAIN']}',", required=False)
# Help/Помощь → /help/, not the API root (which is /_admin/)
sub("src/lang/en.rs", r'\("doc_mac_permission", "[^"]*"\)',
    f'("doc_mac_permission", "{q(HELP)}")', regex=True)
sub("src/lang/en.rs", r'\("doc_fix_wayland", "[^"]*"\)',
    f'("doc_fix_wayland", "{q(HELP)}")', regex=True)
sub("src/client.rs", r'pub const SCRAP_X11_REF_URL: &str = "[^"]*";',
    f'pub const SCRAP_X11_REF_URL: &str = "{q(HELP)}";', regex=True)
sub("src/client.rs", r'(LOGIN_SCREEN_WAYLAND, LoginErrorMsgBox\{[^}]*link: )"[^"]*"',
    rf'\1"{q(HELP)}"', regex=True)

# ---------- 4. Имена приложения / метаданные ----------
sub("Cargo.toml", r'^ProductName = "[^"]*"', f'ProductName = "{q(DISP)}"', regex=True)
sub("Cargo.toml", r'^FileDescription = "[^"]*"', f'FileDescription = "{q(DISP)}"', regex=True)
sub("Cargo.toml", r'^description = "[^"]*"', f'description = "{q(DISP)}"', regex=True, count=1)
sub("Cargo.toml", r'^LegalCopyright = "[^"]*"',
    f'LegalCopyright = "Based on RustDesk (c) Purslane Tech Pte. Ltd., AGPL-3.0; modifications (c) {q(E["COMPANY"])}"', regex=True)
sub("Cargo.toml", r'(\[package\.metadata\.bundle\]\nname = )"[^"]*"\nidentifier = "[^"]*"',
    rf'\1"{q(APP)}"\nidentifier = "{q(E["BUNDLE_ID"])}"', regex=True)
rc = "flutter/windows/runner/Runner.rc"
sub(rc, r'VALUE "CompanyName", "[^"]*"', f'VALUE "CompanyName", "{q(E["COMPANY"])}"', regex=True)
sub(rc, r'VALUE "FileDescription", "[^"]*"', f'VALUE "FileDescription", "{q(DISP)}"', regex=True)
sub(rc, r'VALUE "ProductName", "[^"]*"', f'VALUE "ProductName", "{q(DISP)}"', regex=True)
sub(rc, r'VALUE "LegalCopyright", "[^"]*"',
    f'VALUE "LegalCopyright", "Based on RustDesk, AGPL-3.0. Modifications (c) {q(E["COMPANY"])}"', regex=True)
sub("flutter/windows/runner/main.cpp", 'std::wstring app_name = L"RustDesk";', f'std::wstring app_name = L"{APP}";')
x = "flutter/macos/Runner/Configs/AppInfo.xcconfig"
sub(x, r'^PRODUCT_NAME = .*$', f'PRODUCT_NAME = {APP}', regex=True)
sub(x, r'^PRODUCT_BUNDLE_IDENTIFIER = .*$', f'PRODUCT_BUNDLE_IDENTIFIER = {E["BUNDLE_ID"]}', regex=True)
sub(x, r'^PRODUCT_COPYRIGHT = .*$', f'PRODUCT_COPYRIGHT = Based on RustDesk (AGPL-3.0). Modifications (c) {E["COMPANY"]}', regex=True)
pl = "flutter/macos/Runner/Info.plist"
sub(pl, "<string>com.carriez.rustdesk</string>", f"<string>{E['BUNDLE_ID']}</string>")
sub(pl, "<array>\n\t\t\t\t<string>rustdesk</string>", f"<array>\n\t\t\t\t<string>{APP.lower()}</string>")
if "CFBundleDisplayName" not in (RD / pl).read_text():
    sub(pl, "\t<key>CFBundleExecutable</key>",
        f"\t<key>CFBundleDisplayName</key>\n\t<string>{DISP}</string>\n\t<key>CFBundleExecutable</key>")
# build.py (mac): путь к .app зависит от PRODUCT_NAME
sub("build.py", "Release/RustDesk.app", f"Release/{APP}.app")
sub("build.py", '--volname \\"RustDesk Installer\\"', f'--volname \\"{DISP}\\"', required=False)
wxl = "res/msi/Package/Language/Package.en-us.wxl"
if (RD / wxl).exists():
    raw = (RD / wxl).read_text(encoding="utf-8")
    (RD / wxl).write_text(raw.replace("RustDesk", DISP), encoding="utf-8")

if errors:
    print("ОШИБКИ брендинга (upstream изменился?):", *errors, sep="\n  ", file=sys.stderr)
    sys.exit(1)
print("branding: исходники пропатчены")
PY

# ---------- 5. Иконки и картинки установщиков ----------
# GNU install -D is not BSD install (macOS); copy portably.
cp_req() {
  [ -f "$1" ] || { echo "нет файла дизайна: $1" >&2; exit 1; }
  mkdir -p "$(dirname "$2")"
  cp -f "$1" "$2"
  chmod 644 "$2"
}
I="$DESIGN/icon"; P="$I/png"; S="$DESIGN/installer"
cp_req "$I/icon.ico"            "$RD/res/icon.ico"                                  # exe (build.rs, portable), MSI (preprocess.py -> Package/Resources)
T="$DESIGN/tray"
cp_req "$T/tray-icon.ico"       "$RD/res/tray-icon.ico"                             # трей Windows/Linux: include_bytes! в src/tray.rs
cp_req "$T/mac-tray-dark-x2.png"  "$RD/res/mac-tray-dark-x2.png"                    # трей macOS (template), src/tray.rs
cp_req "$T/mac-tray-light-x2.png" "$RD/res/mac-tray-light-x2.png"                   # не используется кодом 1.5.0, кладём для полноты
cp_req "$I/icon.ico"            "$RD/flutter/windows/runner/resources/app_icon.ico" # Runner.rc IDI_APP_ICON
cp_req "$I/icon.png"            "$RD/res/icon.png"                                  # 256, flutter_launcher_icons
cp_req "$P/mac-1024.png"        "$RD/res/mac-icon.png"
cp_req "$P/win-32.png"          "$RD/res/32x32.png"
cp_req "$P/win-64.png"          "$RD/res/64x64.png"
cp_req "$P/win-128.png"         "$RD/res/128x128.png"
cp_req "$P/win-256.png"         "$RD/res/128x128@2x.png"
cp_req "$I/mac-icon.icns"       "$RD/flutter/macos/Runner/AppIcon.icns"            # Info.plist CFBundleIconFile
cp_req "$I/icon.png"            "$RD/flutter/assets/icon.png"                       # логотип в окне (common.dart loadIcon, трей src/tray.rs)
cp_req "$S/wix-banner-493x58.bmp"  "$RD/res/msi/Package/Resources/WixUIBannerBmp.bmp"  # preprocess.py подхватит автоматически
cp_req "$S/wix-dialog-493x312.bmp" "$RD/res/msi/Package/Resources/WixUIDialogBmp.bmp"
cp_req "$S/dmg-background.png"     "$RD/res/regway/dmg-background.png"                 # для create-dmg --background (CI)
# Portable unpacker splash (rustdesk-portable-packer include_bytes! src/res/label.png).
# Upstream force-tracks this PNG despite root *png gitignore; we copy a 96x32 RegWay wordmark.
cp_req "$S/portable-label.png"     "$RD/libs/portable/src/res/label.png"
[ -f "$S/dmg-background@2x.png" ] && cp_req "$S/dmg-background@2x.png" "$RD/res/regway/dmg-background@2x.png"
echo "branding: иконки разложены"
echo "branding: OK ($APP_NAME, id=$ID_SERVER, relay=$RELAY_SERVER)"
