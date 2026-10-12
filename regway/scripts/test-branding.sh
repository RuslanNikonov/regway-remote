#!/usr/bin/env bash
# Тесты apply-branding.sh / check-branding.sh на временных копиях чистого клона.
# Использование: scripts/test-branding.sh [RUSTDESK_DIR]   (ключ — фиктивный, формата ed25519)
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; SRC="$(cd "${1:-$HERE/rustdesk}" && pwd)"
FK="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="   # фиктивный ключ правильного формата
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; failn=0
fresh() { rm -rf "$TMP/rd"; cp -r "$SRC" "$TMP/rd"; (cd "$TMP/rd" && git checkout -q . && git clean -qfdx -e target && { [ -d libs/hbb_common/.git ] && git -C libs/hbb_common checkout -q . || true; }); }
t() { # name expected_rc env...
  local n="$1" exp="$2"; shift 2; fresh
  env "$@" bash "$HERE/scripts/apply-branding.sh" "$TMP/rd" >"$TMP/o" 2>&1; local rc=$?
  if [ $rc = 0 ]; then env "$@" bash "$HERE/scripts/check-branding.sh" "$TMP/rd" >>"$TMP/o" 2>&1 || rc=2; fi
  local ok=FAIL; { [ "$exp" = 0 ] && [ $rc = 0 ]; } || { [ "$exp" != 0 ] && [ $rc != 0 ]; } && ok=PASS
  [ $ok = PASS ] && pass=$((pass+1)) || failn=$((failn+1))
  printf '%-4s %-34s rc=%s  %s\n' "$ok" "$n" "$rc" "$(rg -m1 'ОШИБКА|KEY не|FAIL|branding: OK' "$TMP/o" | cut -c1-110)"
}
t default_no_require           0
t strict_ok                    0 KEY=$FK REQUIRE_REAL_KEY=1
t strict_placeholder_key       1 REQUIRE_REAL_KEY=1
t strict_id_other_host         1 KEY=$FK REQUIRE_REAL_KEY=1 ID_SERVER=remote2.regway.group
t strict_id_via_RENDEZVOUS     1 KEY=$FK REQUIRE_REAL_KEY=1 RENDEZVOUS_SERVER=evil.example.net
t strict_id_with_port          1 KEY=$FK REQUIRE_REAL_KEY=1 ID_SERVER=remote.regway.group:21116
t strict_relay_port            1 KEY=$FK REQUIRE_REAL_KEY=1 RELAY_SERVER=remote.regway.group:21116
t strict_relay_host            1 KEY=$FK REQUIRE_REAL_KEY=1 RELAY_SERVER=relay.regway.group:21117
t strict_api_http              1 KEY=$FK REQUIRE_REAL_KEY=1 API_SERVER=http://remote.regway.group
t strict_api_slash             1 KEY=$FK REQUIRE_REAL_KEY=1 API_SERVER=https://remote.regway.group/
t strict_api_port              1 KEY=$FK REQUIRE_REAL_KEY=1 API_SERVER=https://remote.regway.group:21114
t strict_api_example           1 KEY=$FK REQUIRE_REAL_KEY=1 API_SERVER=https://remote.example.com
t strict_website_example       1 KEY=$FK REQUIRE_REAL_KEY=1 WEBSITE_URL=https://example.com
# идемпотентность
fresh; bash "$HERE/scripts/apply-branding.sh" "$TMP/rd" >/dev/null 2>&1; h1=$(cd "$TMP/rd" && git diff | sha256sum)
bash "$HERE/scripts/apply-branding.sh" "$TMP/rd" >/dev/null 2>&1; h2=$(cd "$TMP/rd" && git diff | sha256sum)
[ "$h1" = "$h2" ] && { echo "PASS idempotent"; pass=$((pass+1)); } || { echo "FAIL idempotent"; failn=$((failn+1)); }
# check-branding на непропатченном дереве должен падать
fresh; bash "$HERE/scripts/check-branding.sh" "$TMP/rd" >/dev/null 2>&1 && { echo "FAIL check on pristine passed"; failn=$((failn+1)); } || { echo "PASS check on pristine fails"; pass=$((pass+1)); }
# After branding: no :21114 / http://remote.regway.group in built sources; host branch uses https
fresh
KEY=$FK bash "$HERE/scripts/apply-branding.sh" "$TMP/rd" >/dev/null 2>&1
if grep -q 'host.eq_ignore_ascii_case("remote.regway.group")' "$TMP/rd/src/common.rs" \
   && grep -q 'HARD_SETTINGS: RwLock<HashMap<String, String>> = RwLock::new(HashMap::from(\[("api-server"' "$TMP/rd/libs/hbb_common/src/config.rs" \
   && [ -f "$TMP/rd/libs/portable/src/res/label.png" ] \
   && ! grep -R -F -n ':21114' --include='*.rs' --include='*.dart' "$TMP/rd/src" "$TMP/rd/libs" "$TMP/rd/flutter/lib" >/dev/null 2>&1 \
   && ! grep -R -F -n 'http://remote.regway.group' --include='*.rs' --include='*.dart' "$TMP/rd/src" "$TMP/rd/libs" "$TMP/rd/flutter/lib" >/dev/null 2>&1; then
  echo "PASS branded tree has https API host branch, label.png, no :21114/http://remote.regway.group"; pass=$((pass+1))
else
  echo "FAIL branded tree still has :21114 or missing host branch/label.png"; failn=$((failn+1))
fi
# check-branding must fail if http://host:21114 is reintroduced
printf '\nfn _regway_poison() { let _ = "http://remote.regway.group:21114"; }\n' >> "$TMP/rd/src/common.rs"
if KEY=$FK REQUIRE_REAL_KEY=1 bash "$HERE/scripts/check-branding.sh" "$TMP/rd" >/dev/null 2>&1; then
  echo "FAIL check-branding missed :21114 poison"; failn=$((failn+1))
else
  echo "PASS check-branding rejects :21114 / http://remote.regway.group"; pass=$((pass+1))
fi
echo "== $pass passed, $failn failed"; [ $failn = 0 ]
