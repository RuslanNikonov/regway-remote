#!/usr/bin/env bash
# Проверка: после apply-branding.sh в коде, влияющем на подключение, нет серверов RustDesk.
# Допустимые остатки (allowlist) — только тесты/комментарии/детектор is_public(), см. README.
set -euo pipefail
RD="${1:-$(dirname "$0")/../rustdesk}"
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
ALLOW='^(src/common\.rs:(1031|117[0-9]|3[0-9]{3}):|libs/hbb_common/src/socket_client\.rs:3(1[0-9]|2[0-9]):|libs/hbb_common/src/websocket\.rs:(4[89][0-9]|5[0-9]{2}):)'
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
need libs/hbb_common/src/config.rs '("hide-server-settings".to_owned(), "Y".to_owned())' "раздел сервера скрыт"
rg -q '"relay-server"\.to_owned\(\), "[A-Za-z0-9.-]+:21117"' libs/hbb_common/src/config.rs \
  && echo "OK   relay = <хост>:21117" || { echo "FAIL relay не <хост>:21117"; fail=1; }
# в коде не должно остаться неотключённого разбора имени exe
if rg -n '^\s*get_custom_server_from_string\(&exe\)\s*$' src/platform/windows.rs; then echo "FAIL разбор имени exe активен"; fail=1; fi
need src/lang/ru.rs '("Closed manually by web console", "Сеанс завершён администратором"),' "ru: «Сеанс завершён администратором»"
need src/common.rs '"https://remote.regway.group".to_owned()' "fallback API = https://remote.regway.group (без порта)"
need src/common.rs 'let api_http_port = config::RENDEZVOUS_PORT - 2;' "strip https API-порта через RENDEZVOUS_PORT-2, без литерала :21114"
# :21114 must not appear in built sources. Tests that assert its absence live in regway/scripts/.
if hits21114="$(rg -n -F ':21114' src libs flutter/lib || true)" && [ -n "$hits21114" ]; then
  echo "FAIL :21114 в исходниках сборки:"
  echo "$hits21114"
  fail=1
else
  echo "OK   :21114 нет в src/ libs/ flutter/lib/"
fi
# Строгий режим (CI релиза): хосты ровно remote.regway.group
if [ "${REQUIRE_REAL_KEY:-0}" = 1 ]; then
  H=remote.regway.group
  need libs/hbb_common/src/config.rs "pub const RENDEZVOUS_SERVERS: &[&str] = &[\"$H\"];" "strict: RENDEZVOUS_SERVERS = $H"
  need libs/hbb_common/src/config.rs "(\"custom-rendezvous-server\".to_owned(), \"$H\".to_owned())" "strict: ID = $H"
  need libs/hbb_common/src/config.rs "(\"relay-server\".to_owned(), \"$H:21117\".to_owned())" "strict: relay = $H:21117"
  need libs/hbb_common/src/config.rs "(\"api-server\".to_owned(), \"https://$H\".to_owned())" "strict: API = https://$H"
  if rg -q 'pub const RS_PUB_KEY: &str = "REPLACE_' libs/hbb_common/src/config.rs; then echo "FAIL strict: ключ-плейсхолдер"; fail=1; else echo "OK   strict: ключ не плейсхолдер"; fi
fi
exit $fail
