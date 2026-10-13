#!/usr/bin/env bash
# Проверка: после apply-branding.sh в коде, влияющем на подключение, нет серверов RustDesk.
# Допустимые остатки (allowlist) — только тесты/комментарии/детектор is_public(), см. README.
set -euo pipefail
# Windows GitHub runners use cp1252 for Python stdout; keep UTF-8 for Cyrillic logs.
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
RD="${1:-$(dirname "$0")/../rustdesk}"
# shellcheck source=hbbs-key.sh
source "$(cd "$(dirname "$0")" && pwd)/hbbs-key.sh"
cd "$RD"

# GitHub-hosted runners do not ship ripgrep; keep the same checks via grep.
rg() {
  # type -P looks up PATH only, so this function does not shadow a missing binary.
  if [ -z "${REGWAY_FORCE_GREP:-}" ] && [ -n "$(type -P rg 2>/dev/null)" ]; then
    command rg "$@"
    return
  fi
  local grep_args=() has_F=0 recursive=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -n|-i|-q|-v|-c) grep_args+=("$1"); shift ;;
      -F) grep_args+=(-F); has_F=1; shift ;;
      --) shift; break ;;
      -*) echo "unsupported rg flag: $1" >&2; return 2 ;;
      *) break ;;
    esac
  done
  [ "$has_F" -eq 0 ] && grep_args+=(-E)
  local pattern="$1"; shift
  if [ $# -gt 0 ]; then
    local p
    for p in "$@"; do
      if [ -d "$p" ]; then recursive=1; break; fi
    done
  fi
  [ "$recursive" -eq 1 ] && grep_args+=(-R -I)
  grep "${grep_args[@]}" -- "$pattern" "$@"
}

PAT='rustdesk\.com|rs-ny|rs-sg|rs-cn'
ALLOW='^(src/common\.rs:(103[0-9]|11[6-9][0-9]|3[0-9]{3}):|libs/hbb_common/src/socket_client\.rs:3(1[0-9]|2[0-9]):|libs/hbb_common/src/websocket\.rs:(4[89][0-9]|5[0-9]{2}):)'
hits="$(rg -n -i "$PAT" src libs/hbb_common/src flutter/lib || true)"
bad="$(printf '%s\n' "$hits" | rg -v "$ALLOW" | rg -v '^$' || true)"
echo "== всего совпадений: $(printf '%s\n' "$hits" | rg -c . || echo 0); вне allowlist:"
if [ -n "$bad" ]; then echo "$bad"; exit 1; fi
echo "(пусто) OK"
# встроенные значения
rg -n 'pub const RENDEZVOUS_SERVERS|pub const RS_PUB_KEY|PROD_RENDEZVOUS_SERVER: RwLock' libs/hbb_common/src/config.rs

fail=0
need() { # file pattern description
  if rg -q -F -- "$2" "$1"; then echo "OK   $3"; else echo "FAIL $3 ($1)"; fail=1; fi
}
echo "== защитные патчи"
need src/platform/windows.rs 'hbb_common::bail!("exe-name server override disabled")' "Windows: сервер/ключ из имени exe отключены (get_license_from_exe_name)"
need src/platform/windows.rs 'if true || lic.key.is_empty() || lic.host.is_empty() { // RegWay' "Windows: install_me не берёт сервер из реестра/имени exe"
need src/core_main.rs 'if false && args.len() == 2 { // RegWay' "CLI --config <строка сервера> отключён"
need src/tray.rs '.filter(|_| false) // RegWay' "трей использует res/tray-icon.ico / res/mac-tray-dark-x2.png"
rg -q '"api-server"\.to_owned\(\), "https://[A-Za-z0-9.-]+"' libs/hbb_common/src/config.rs \
  && echo "OK   API = https://<хост> (OVERWRITE_SETTINGS)" || { echo "FAIL API не https://<хост>"; fail=1; }
if rg -q '\("register-device"\.to_owned\(\)' libs/hbb_common/src/config.rs; then echo "FAIL register-device задан (отключит API)"; fail=1; else echo "OK   register-device не задан (логин/heartbeat/audit работают)"; fi
need src/hbbs_http/sync.rs 'Ok((401, _)) if !token.is_empty() => {' "heartbeat: реакция только на HTTP 401 при отправленном токене"
need src/hbbs_http/sync.rs 'fn regway_revoke_sessions(token: &str)' "heartbeat: закрытие входящих сеансов + сброс токена"
need src/login_gate.rs 'pub const CHECK_INTERVAL: Duration = Duration::from_secs(30);' "login-gate: 30s token heartbeat"
need src/login_gate.rs 'pub const CHECK_INTERVAL_OFFLINE: Duration = Duration::from_secs(10);' "login-gate: 10s poll while API unreachable"
need src/login_gate.rs 'pub const CONFIRM_TTL: Duration = Duration::from_secs(60);' "login-gate: 60s confirm TTL, no 24h grace"
if rg -q 'OFFLINE_GRACE' src/login_gate.rs; then echo "FAIL 24h OFFLINE_GRACE still in login_gate.rs"; fail=1; else echo "OK   24h offline grace removed"; fi
need src/login_gate.rs 'fn suspend(reason: &str)' "login-gate: suspend sessions, keep token"
need src/login_gate.rs 'log, tokio, ResultType,' "login-gate: tokio via hbb_common (not a crate dep)"
need src/login_gate.rs 'pub fn decide_auth_check(status: Option<u16>, body: &str) -> AuthCheckOutcome' "login-gate: 401 revoke / network grace"
need src/login_gate.rs 'fn http_401_unauthorized_revokes' "login-gate: unit test 401 → revoke"
need src/login_gate.rs 'fn network_error_uses_grace_not_revoke' "login-gate: unit test network error → grace"
need src/server.rs 'crate::login_gate::refuse_incoming()' "login-gate: incoming refused without token"
need src/client.rs 'crate::login_gate::refuse_outgoing()' "login-gate: outgoing refused without token"
if rg -q 'login_gate::is_session_allowed()' src/rendezvous_mediator.rs; then echo "FAIL rendezvous gated on login (hbbs must register at boot)"; fail=1; else echo "OK   rendezvous starts at boot (not gated on login)"; fi
need flutter/lib/regway/login_view.dart 'return Scaffold(' "login-gate: overlay wrapped in Scaffold/Material"
need flutter/lib/regway/shell.dart 'class _RwWordmark extends StatelessWidget' "sidebar two-line wordmark RegWay / Remote"
need flutter/lib/regway/shell.dart 'letterSpacing: 0.04 * 12,' "wordmark Remote letter-spacing 0.04em"
need flutter/lib/regway/computers.dart 'final statusNum = model.connectStatus;' "status widget uses real connect-status stream"
need flutter/lib/regway/computers.dart "bind.mainGetLocalOption(key: 'rw-api-reachable') == 'N'" "status plaque reads rw-api-reachable"
need flutter/lib/regway/computers.dart "translate('No server connection')" "API-offline banner: Нет связи с сервером"
need flutter/lib/common/widgets/overlay.dart "translate('— ms')" "quality Delay: grey em-dash when no session data"
need flutter/lib/regway/quality_pill.dart 'const double kRwQualityDelayGoodMs = 80;' "quality v3: delay good ≤ 80 ms"
need flutter/lib/regway/quality_pill.dart 'const double kRwQualityDelayBadMs = 200;' "quality v3: delay red > 200 ms"
need flutter/lib/regway/quality_pill.dart 'final band = rwQualityBand(delayMs: avgDelay);' "quality: colour from delay only, not frame-loss"
need src/lang/ru.rs '("Packet loss: —", "Потери кадров: —"),' "quality tooltip: Потери кадров"
need flutter/lib/regway/quality_pill.dart 'const Duration kRwQualityAvgWindow = Duration(seconds: 3);' "quality v3: 3 s average"
need flutter/lib/regway/quality_pill.dart 'const Duration kRwQualityStaleAfter = Duration(seconds: 3);' "quality v3: grey if no data > 3 s"
need flutter/lib/regway/quality_pill.dart 'const Duration kRwQualityColorHold = Duration(seconds: 2);' "quality v3: color hold 2 s"
need flutter/lib/regway/quality_pill.dart 'class _RwSignalBars extends StatelessWidget' "quality v3: 3 signal bars"
need flutter/lib/regway/quality_pill.dart "translate('Via relay')" "quality v3 tooltip: Напрямую / Через relay"
need flutter/lib/desktop/widgets/remote_toolbar.dart 'RwQualityPill(id: widget.id, ffi: widget.ffi)' "quality v3 pill overlaid top-right on session toolbar"
need flutter/lib/models/user_model.dart 'static const int confirmTtlSecs = 60;' "Flutter heartbeat: 60 s confirm TTL, no 24h grace"
need src/login_gate.rs 'pub const API_REACHABLE: &str = "rw-api-reachable";' "login-gate: rw-api-reachable Y/N"
need src/login_gate.rs 'fn timeout_does_not_revoke()' "login-gate: unit test timeout → grace, not revoke"
need src/platform/macos.rs 'pub fn ensure_server_after_login()' "macOS: start --server after login"
need src/platform/macos.rs 'std::time::Duration::from_millis(super::SERVICE_INTERVAL)' "macOS --server watchdog uses SERVICE_INTERVAL"
need flutter/lib/models/user_model.dart 'Future<void> refreshCurrentUser() async' "login-gate: refreshCurrentUser is awaitable (not void)"
need src/platform/privileges_scripts/install.scpt 'launchctl kickstart -k system/' "macOS install: kickstart -k replaces old root service"
need flutter/lib/regway/login_view.dart 'class RwLoginPage extends StatelessWidget' "login-gate: full-window Flutter gate"
need flutter/lib/regway/widgets.dart 'bg = hover && enabled ? p.dangerHover : p.danger' "redesign: solid danger disconnect"
need flutter/lib/regway/theme.dart 'static const Color accent = Color(0xFF38D9FF);' "redesign: solid accent #38d9ff"
need flutter/lib/regway/theme.dart 'static const Color card = Color(0xFF15123A);' "v2 dark cards #15123a"
need flutter/lib/regway/theme.dart 'accent: Color(0xFF0A9CC2),' "v2 light buttons/switches #0a9cc2"
need flutter/lib/regway/theme.dart 'danger: Color(0xFFD41E48),' "v2 light Отключиться #d41e48"
need flutter/lib/desktop/pages/desktop_setting_page.dart "// Theme: Системная / Тёмная / Светлая (system, dark, light)" "theme radios: system / dark / light"
need src/lang/ru.rs '("UserDisabled", "Аккаунт отключён администратором"),' "login-gate: UserDisabled ru"
need src/lang/en.rs '("UserDisabled", "Account disabled by administrator"),' "login-gate: UserDisabled en"
need flutter/lib/common.dart "if (name == 'RegWayRemote') return 'RegWay Remote';" "window title uses display name"
need src/tray.rs '"RegWay Remote".to_owned()' "tray tooltip uses display name"
need flutter/macos/Runner/Info.plist "<string>RegWay Remote</string>" "macOS CFBundleDisplayName"
need flutter/ios/Runner/Info.plist "<string>RegWay Remote</string>" "iOS CFBundleDisplayName"
need res/rustdesk.desktop "Name=RegWay Remote" "desktop Name="
need res/msi/Package/Language/Package.en-us.wxl 'Value="RegWay Remote"' "MSI product strings"
need libs/hbb_common/src/config.rs '("hide-server-settings".to_owned(), "Y".to_owned())' "раздел сервера скрыт"
rg -q '"relay-server"\.to_owned\(\), "[A-Za-z0-9.-]+:21117"' libs/hbb_common/src/config.rs \
  && echo "OK   relay = <хост>:21117" || { echo "FAIL relay не <хост>:21117"; fail=1; }
# в коде не должно остаться неотключённого разбора имени exe
if rg -n '^\s*get_custom_server_from_string\(&exe\)\s*$' src/platform/windows.rs; then echo "FAIL разбор имени exe активен"; fail=1; fi
need src/lang/ru.rs '("Closed manually by web console", "Сеанс завершён администратором"),' "ru: «Сеанс завершён администратором»"
need src/common.rs '"https://remote.regway.group".to_owned()' "fallback API = https://remote.regway.group (без порта)"
need src/common.rs 'host.eq_ignore_ascii_case("remote.regway.group")' "get_api_server_: наш ID-хост → https://remote.regway.group, не http://host:21114"
need src/common.rs 'let api_http_port = config::RENDEZVOUS_PORT - 2;' "strip https API-порта через RENDEZVOUS_PORT-2, без литерала :21114"
need libs/hbb_common/src/config.rs 'pub static ref HARD_SETTINGS: RwLock<HashMap<String, String>> = RwLock::new(HashMap::from([("api-server"' "HARD_SETTINGS api-server зашит"
if [ -f libs/portable/src/res/label.png ]; then
  echo "OK   libs/portable/src/res/label.png (portable packer splash)"
else
  echo "FAIL нет libs/portable/src/res/label.png (rustdesk-portable-packer include_bytes)"
  fail=1
fi
# :21114 / http://remote.regway.group must not appear in built sources.
if hits21114="$(rg -n -F ':21114' src libs flutter/lib || true)" && [ -n "$hits21114" ]; then
  echo "FAIL :21114 в исходниках сборки:"
  echo "$hits21114"
  fail=1
else
  echo "OK   :21114 нет в src/ libs/ flutter/lib/"
fi
if hitshttp="$(rg -n -F 'http://remote.regway.group' src libs flutter/lib || true)" && [ -n "$hitshttp" ]; then
  echo "FAIL http://remote.regway.group в исходниках сборки:"
  echo "$hitshttp"
  fail=1
else
  echo "OK   http://remote.regway.group нет в src/ libs/ flutter/lib/"
fi
# User-visible "RustDesk" in UI strings. Allowed: AGPL attribution
# ("based on RustDesk (AGPL-3.0)" / "Based on RustDesk") and lookup keys.
echo "== видимый RustDesk в UI"
python3 - "$RD" <<'PY' || fail=1
import re, sys
from pathlib import Path
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass
root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
allowed_val = re.compile(
    r"based on RustDesk \(AGPL-3\.0\)|Based on RustDesk",
    re.I,
)
fail = 0
lang_line = re.compile(r'^\s*\("([^"]*)", "(.*)"\),?\s*$')
for p in sorted((root / "src/lang").glob("*.rs")):
    for i, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        m = lang_line.match(line)
        if not m:
            continue
        val = m.group(2)
        if "RustDesk" not in val and "Rustdesk" not in val:
            continue
        stripped = allowed_val.sub("", val)
        if re.search(r"RustDesk|Rustdesk", stripped):
            print(f"FAIL visible RustDesk {p.relative_to(root)}:{i}: {val[:120]}")
            fail = 1
# Flutter UI literals (skip comments, debug, keys passed to translate, AGPL).
ui_dirs = [
    root / "flutter/lib",
    root / "res/msi/Package/Language",
]
skip_re = re.compile(
    r"debugPrint|RustDeskTerminal|translate\(|About RustDesk|Keep RustDesk|Show RustDesk|"
    r"based on RustDesk|Based on RustDesk|is_custom_client|mainGetAppNameSync|"
    r"com\.rustdesk|com\.carriez|//",
    re.I,
)
lit = re.compile(r'''(['"])(.*?)(\1)''')
xml_string = re.compile(r"<string>([^<]*)</string>", re.I)
desktop_name = re.compile(r"^(Name|GenericName|Comment|Value)=(.*)$")
extra_files = [
    root / "flutter/macos/Runner/Info.plist",
    root / "flutter/ios/Runner/Info.plist",
    root / "flutter/android/app/src/main/res/values/strings.xml",
    root / "flutter/android/app/src/main/AndroidManifest.xml",
    root / "res/rustdesk.desktop",
    root / "res/rustdesk-link.desktop",
]
def report_visible(path, lineno, text):
    global fail
    stripped = allowed_val.sub("", text)
    if re.search(r"RustDesk|Rustdesk", stripped):
        print(f"FAIL visible RustDesk {path.relative_to(root)}:{lineno}: {text[:120]}")
        fail = 1
for d in ui_dirs:
    if not d.exists():
        continue
    for p in d.rglob("*"):
        if p.suffix.lower() not in {".dart", ".wxl"}:
            continue
        for i, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if skip_re.search(line):
                continue
            for m in lit.finditer(line):
                s = m.group(2)
                if "RustDesk" in s or "Rustdesk" in s:
                    report_visible(p, i, s)
for p in extra_files:
    if not p.exists():
        continue
    for i, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if "<!--" in line or skip_re.search(line):
            continue
        for m in xml_string.finditer(line):
            if "RustDesk" in m.group(1) or "Rustdesk" in m.group(1):
                report_visible(p, i, m.group(1))
        m = desktop_name.match(line.strip())
        if m and ("RustDesk" in m.group(2) or "Rustdesk" in m.group(2)):
            report_visible(p, i, m.group(2))
        for m in lit.finditer(line):
            s = m.group(2)
            if "RustDesk" in s or "Rustdesk" in s:
                report_visible(p, i, s)
if fail:
    sys.exit(1)
print("OK   нет пользовательского RustDesk вне AGPL attribution")
PY

# Строгий режим (CI релиза): хосты ровно remote.regway.group
if [ "${REQUIRE_REAL_KEY:-0}" = 1 ]; then
  H=remote.regway.group
  need libs/hbb_common/src/config.rs "pub const RENDEZVOUS_SERVERS: &[&str] = &[\"$H\"];" "strict: RENDEZVOUS_SERVERS = $H"
  need libs/hbb_common/src/config.rs "(\"custom-rendezvous-server\".to_owned(), \"$H\".to_owned())" "strict: ID = $H"
  need libs/hbb_common/src/config.rs "(\"relay-server\".to_owned(), \"$H:21117\".to_owned())" "strict: relay = $H:21117"
  need libs/hbb_common/src/config.rs "(\"api-server\".to_owned(), \"https://$H\".to_owned())" "strict: API = https://$H"
  need libs/hbb_common/src/config.rs "pub static ref HARD_SETTINGS: RwLock<HashMap<String, String>> = RwLock::new(HashMap::from([(\"api-server\".to_owned(), \"https://$H\".to_owned())]));" "strict: HARD_SETTINGS api-server = https://$H"
  if rg -q 'pub const RS_PUB_KEY: &str = "REPLACE_' libs/hbb_common/src/config.rs; then echo "FAIL strict: ключ-плейсхолдер"; fail=1; else echo "OK   strict: ключ не плейсхолдер"; fi
  # Exact hbbs public key: fingerprint only, never print the full key.
  got_key="$(python3 -c '
import re, pathlib, sys
s = pathlib.Path("libs/hbb_common/src/config.rs").read_text(encoding="utf-8")
m = re.search(r"pub const RS_PUB_KEY: &str = \"([^\"]*)\";", s)
sys.stdout.write(m.group(1) if m else "")
')"
  echo "compiled RS_PUB_KEY fingerprint: $(hbbs_key_fingerprint "$got_key")"
  echo "expected hbbs fingerprint:       $(hbbs_key_fingerprint "$EXPECTED_HBBS_PUB_KEY")"
  if [ "$got_key" != "$EXPECTED_HBBS_PUB_KEY" ]; then
    echo "FAIL strict: compiled RS_PUB_KEY != expected hbbs public key"
    echo "  compiled: $(hbbs_key_fingerprint "$got_key")"
    echo "  expected: $(hbbs_key_fingerprint "$EXPECTED_HBBS_PUB_KEY")"
    echo "  GitHub secret RS_PUB_KEY cannot be changed from this script."
    fail=1
  else
    echo "OK   strict: compiled RS_PUB_KEY matches expected hbbs public key"
  fi
  if ! rg -q -F -- "$EXPECTED_HBBS_PUB_KEY" libs/hbb_common/src/config.rs; then
    echo "FAIL strict: expected hbbs public key string not in config.rs"
    fail=1
  else
    echo "OK   strict: expected hbbs public key string is in config.rs"
  fi
fi
exit $fail
