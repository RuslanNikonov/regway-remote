//! Mandatory account login gate for RegWay Remote.
//!
//! Incoming and outgoing sessions are refused unless a rustdesk-api access token
//! is present and has been confirmed by `/api/currentUser` within [`CONFIRM_TTL`].
//! The same check runs in the UI process and in `--server`.
//!
//! Verified rustdesk-api behaviour:
//! - a disabled user's existing token on `POST /api/currentUser` → HTTP 401
//!   `{"error":"Unauthorized"}` → [`AuthCheckOutcome::Revoke`] (login screen)
//! - `POST /api/login` for a disabled user → HTTP 400 `{"error":"UserDisabled"}`
//!   (shown on the Flutter gate; not this heartbeat)
//! - a transport / network error is **not** a 401 → [`AuthCheckOutcome::Unreachable`].
//!   After [`CONFIRM_TTL`] without a 200, sessions are suspended (closed, new
//!   ones refused) but the token is kept. A later 200 restores access with no
//!   re-login.

use hbb_common::{
    anyhow::anyhow,
    config::{Config, LocalConfig},
    log, tokio, ResultType,
};
use serde_json::{json, Value};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Once;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Sessions stay allowed only this long after the last successful currentUser.
pub const CONFIRM_TTL: Duration = Duration::from_secs(60);

/// How often `/api/currentUser` is polled while the API last confirmed the user.
/// Aim 30 s so a disable/delete in `/_admin/` drops every session within 60 s.
pub const CHECK_INTERVAL: Duration = Duration::from_secs(30);

/// Faster poll while the API is unreachable so recovery (and the 60 s suspend)
/// is not stuck behind the online interval.
pub const CHECK_INTERVAL_OFFLINE: Duration = Duration::from_secs(10);

pub const TOKEN_VALIDATED_AT: &str = "rw-token-validated-at";
pub const LOGIN_OK: &str = "rw-login-ok";
pub const LOGIN_TOKEN: &str = "rw-login-token";
/// `Y` after a successful `/api/currentUser`. `N` after sessions are suspended
/// because the API was unreachable for [`CONFIRM_TTL`]. Empty when there is no token.
pub const API_REACHABLE: &str = "rw-api-reachable";
const ACCESS_TOKEN: &str = "access_token";

static LAST_API_OK: AtomicBool = AtomicBool::new(false);
static SESSIONS_SUSPENDED: AtomicBool = AtomicBool::new(false);

/// Result of one `/api/currentUser` (or equivalent) check. Pure: no I/O.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthCheckOutcome {
    /// Token is valid; refresh the confirm timestamp.
    Allow,
    /// HTTP 401/403/400, disabled/deleted user, or an explicit error body.
    Revoke,
    /// Transport failure or unexpected HTTP. Keep the token; suspend after TTL.
    Unreachable,
}

pub fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn token_from_local() -> String {
    LocalConfig::get_option(ACCESS_TOKEN)
}

fn token_from_server_config() -> String {
    Config::get_option(LOGIN_TOKEN)
}

/// Bearer token visible to this process (UI LocalConfig or server Config2 copy).
pub fn access_token() -> String {
    let t = token_from_local();
    if !t.is_empty() {
        return t;
    }
    token_from_server_config()
}

fn validated_at() -> Option<u64> {
    for src in [
        LocalConfig::get_option(TOKEN_VALIDATED_AT),
        Config::get_option(TOKEN_VALIDATED_AT),
    ] {
        if let Ok(n) = src.parse::<u64>() {
            if n > 0 {
                return Some(n);
            }
        }
    }
    None
}

pub fn is_within_confirm_ttl() -> bool {
    match validated_at() {
        Some(ts) => unix_now().saturating_sub(ts) < CONFIRM_TTL.as_secs(),
        None => false,
    }
}

/// Hot path: no network. Used by accept, connect, CLI.
pub fn is_session_allowed() -> bool {
    if access_token().is_empty() && Config::get_option(LOGIN_OK) != "Y" {
        return false;
    }
    is_within_confirm_ttl()
}

pub fn poll_interval() -> Duration {
    if LAST_API_OK.load(Ordering::Relaxed) {
        CHECK_INTERVAL
    } else {
        CHECK_INTERVAL_OFFLINE
    }
}

fn set_api_reachable(ok: Option<bool>) {
    let v = match ok {
        Some(true) => "Y",
        Some(false) => "N",
        None => "",
    };
    LocalConfig::set_option(API_REACHABLE.to_owned(), v.to_owned());
    Config::set_option(API_REACHABLE.to_owned(), v.to_owned());
}

pub fn mark_validated() {
    let now = unix_now().to_string();
    LocalConfig::set_option(TOKEN_VALIDATED_AT.to_owned(), now.clone());
    Config::set_option(TOKEN_VALIDATED_AT.to_owned(), now);
    Config::set_option(LOGIN_OK.to_owned(), "Y".to_owned());
    set_api_reachable(Some(true));
    LAST_API_OK.store(true, Ordering::SeqCst);
    SESSIONS_SUSPENDED.store(false, Ordering::SeqCst);
    let token = access_token();
    if !token.is_empty() {
        Config::set_option(LOGIN_TOKEN.to_owned(), token);
    }
    log::info!("login-gate: token validated");
}

pub fn on_access_token_changed(value: &str) {
    if value.is_empty() {
        revoke("access_token cleared");
    } else {
        Config::set_option(LOGIN_TOKEN.to_owned(), value.to_owned());
        mark_validated();
    }
}

/// Forget the token, close every incoming and outgoing session, stop accepting.
/// Caller is bounced to the login screen.
pub fn revoke(reason: &str) {
    log::warn!("login-gate: revoke ({reason})");
    if !LocalConfig::get_option(ACCESS_TOKEN).is_empty() {
        LocalConfig::set_option(ACCESS_TOKEN.to_owned(), "".to_owned());
        LocalConfig::set_option("user_info".to_owned(), "".to_owned());
    }
    LocalConfig::set_option(TOKEN_VALIDATED_AT.to_owned(), "".to_owned());
    Config::set_option(LOGIN_OK.to_owned(), "N".to_owned());
    Config::set_option(LOGIN_TOKEN.to_owned(), "".to_owned());
    Config::set_option(TOKEN_VALIDATED_AT.to_owned(), "".to_owned());
    set_api_reachable(None);
    LAST_API_OK.store(false, Ordering::SeqCst);
    SESSIONS_SUSPENDED.store(false, Ordering::SeqCst);
    close_incoming();
    close_outgoing();
}

/// API unreachable for [`CONFIRM_TTL`]: close sessions and refuse new ones,
/// but keep the token so a later currentUser 200 restores access with no re-login.
fn suspend(reason: &str) {
    LAST_API_OK.store(false, Ordering::SeqCst);
    set_api_reachable(Some(false));
    if SESSIONS_SUSPENDED.swap(true, Ordering::SeqCst) {
        return;
    }
    log::warn!("login-gate: suspend ({reason}); token kept, no re-login");
    close_incoming();
    close_outgoing();
}

fn close_incoming() {
    #[cfg(not(any(target_os = "ios")))]
    crate::hbbs_http::sync::close_alive_incoming();
}

fn close_outgoing() {
    #[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
    {
        let n = crate::flutter::sessions::close_all_sessions();
        if n > 0 {
            log::warn!("login-gate: closed {n} outgoing session(s)");
        }
    }
}

/// Map an HTTP status (or a transport error) plus body to allow / revoke / unreachable.
///
/// `status == None` is a network error (unreachable API, TLS, timeout). That is
/// not a 401: keep the token. A disabled account's token is 401.
pub fn decide_auth_check(status: Option<u16>, body: &str) -> AuthCheckOutcome {
    match status {
        Some(s) if (200..300).contains(&s) => {
            if user_disabled_or_rejected(body) {
                AuthCheckOutcome::Revoke
            } else {
                AuthCheckOutcome::Allow
            }
        }
        Some(401) | Some(403) | Some(400) => AuthCheckOutcome::Revoke,
        Some(_) => AuthCheckOutcome::Unreachable,
        None => AuthCheckOutcome::Unreachable,
    }
}

fn user_disabled_or_rejected(body: &str) -> bool {
    let Ok(v) = serde_json::from_str::<Value>(body) else {
        return false;
    };
    if let Some(err) = v.get("error") {
        let s = err.as_str().unwrap_or("").to_ascii_lowercase();
        if !s.is_empty() {
            return true;
        }
    }
    match v.get("status") {
        Some(Value::Number(n)) => n.as_i64() == Some(0),
        Some(Value::String(s)) => s == "0" || s.eq_ignore_ascii_case("disabled"),
        _ => false,
    }
}

/// POST `/api/currentUser`. Updates the confirm timestamp on success; revokes on
/// 401/disabled. Unreachable API suspends sessions after [`CONFIRM_TTL`] but
/// does not clear the token.
pub async fn revalidate() -> ResultType<bool> {
    let token = access_token();
    if token.is_empty() {
        if Config::get_option(LOGIN_OK) == "Y" {
            revoke("no token");
        }
        return Ok(false);
    }
    let api = crate::get_api_server(
        Config::get_option("api-server"),
        Config::get_option("custom-rendezvous-server"),
    );
    if api.is_empty() {
        return Ok(apply_outcome(AuthCheckOutcome::Unreachable, "no api-server"));
    }
    let url = format!("{}/api/currentUser", api.trim_end_matches('/'));
    let body = json!({
        "id": Config::get_id(),
        "uuid": crate::encode64(hbb_common::get_uuid()),
    })
    .to_string();
    let header = format!("Authorization: Bearer {}", token);
    let (status, resp_body) = match crate::post_request_with_status(url, body, &header).await {
        Ok((status, body)) => (Some(status), body),
        Err(err) => {
            // Timeout / DNS / TLS: not a 401. Keep the token.
            log::warn!("login-gate: currentUser unreachable (network timeout/error, not 401): {err:?}");
            return Ok(apply_outcome(AuthCheckOutcome::Unreachable, "network timeout"));
        }
    };
    let outcome = decide_auth_check(status, &resp_body);
    let reason = match (status, outcome) {
        (Some(401), AuthCheckOutcome::Revoke) => {
            "API 401 Unauthorized (disabled/deleted or invalid token)"
        }
        (Some(403), AuthCheckOutcome::Revoke) => "API 403",
        (Some(400), AuthCheckOutcome::Revoke) => "API 400",
        (_, AuthCheckOutcome::Revoke) => "account disabled or deleted",
        (Some(s), AuthCheckOutcome::Unreachable) => {
            log::warn!("login-gate: currentUser HTTP {s}, treating as unreachable");
            "unexpected HTTP"
        }
        _ => "ok",
    };
    Ok(apply_outcome(outcome, reason))
}

fn apply_outcome(outcome: AuthCheckOutcome, reason: &str) -> bool {
    match outcome {
        AuthCheckOutcome::Allow => {
            mark_validated();
            true
        }
        AuthCheckOutcome::Revoke => {
            revoke(reason);
            false
        }
        AuthCheckOutcome::Unreachable => {
            LAST_API_OK.store(false, Ordering::SeqCst);
            if is_within_confirm_ttl() {
                log::warn!(
                    "login-gate: API unreachable ({reason}); sessions still allowed until confirm TTL"
                );
                true
            } else {
                suspend(reason);
                false
            }
        }
    }
}

pub fn refuse_incoming() -> ResultType<()> {
    if is_session_allowed() {
        Ok(())
    } else {
        Err(anyhow!("login-gate: incoming refused (not logged in)"))
    }
}

pub fn refuse_outgoing() -> ResultType<()> {
    if is_session_allowed() {
        Ok(())
    } else {
        Err(anyhow!("login-gate: outgoing refused (not logged in)"))
    }
}

/// Background poll so `--server` and the UI process re-gate without waiting
/// on Flutter. Idempotent (Once).
pub fn start_periodic_check() {
    static START: Once = Once::new();
    START.call_once(|| {
        std::thread::Builder::new()
            .name("login-gate".into())
            .spawn(|| {
                let rt = tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build();
                let Ok(rt) = rt else {
                    log::error!("login-gate: failed to start tokio runtime");
                    return;
                };
                rt.block_on(async {
                    tokio::time::sleep(Duration::from_secs(2)).await;
                    loop {
                        let _ = revalidate().await;
                        tokio::time::sleep(poll_interval()).await;
                    }
                });
            })
            .ok();
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn http_401_unauthorized_revokes() {
        assert_eq!(
            decide_auth_check(Some(401), r#"{"error":"Unauthorized"}"#),
            AuthCheckOutcome::Revoke
        );
    }

    #[test]
    fn http_403_revokes() {
        assert_eq!(decide_auth_check(Some(403), ""), AuthCheckOutcome::Revoke);
    }

    #[test]
    fn http_400_user_disabled_revokes() {
        assert_eq!(
            decide_auth_check(Some(400), r#"{"error":"UserDisabled"}"#),
            AuthCheckOutcome::Revoke
        );
    }

    #[test]
    fn network_error_uses_grace_not_revoke() {
        assert_eq!(
            decide_auth_check(None, ""),
            AuthCheckOutcome::Unreachable
        );
    }

    #[test]
    fn timeout_does_not_revoke() {
        // post_request_with_status Err (timeout) is mapped to status=None.
        assert_eq!(
            decide_auth_check(None, "timed out"),
            AuthCheckOutcome::Unreachable
        );
        assert_ne!(
            decide_auth_check(None, "timed out"),
            AuthCheckOutcome::Revoke
        );
    }

    #[test]
    fn unexpected_http_uses_grace() {
        assert_eq!(
            decide_auth_check(Some(502), "bad gateway"),
            AuthCheckOutcome::Unreachable
        );
        assert_eq!(
            decide_auth_check(Some(500), ""),
            AuthCheckOutcome::Unreachable
        );
    }

    #[test]
    fn ok_user_allows() {
        assert_eq!(
            decide_auth_check(Some(200), r#"{"name":"alice","status":1}"#),
            AuthCheckOutcome::Allow
        );
    }

    #[test]
    fn disabled_status_on_200_revokes() {
        assert_eq!(
            decide_auth_check(Some(200), r#"{"name":"alice","status":0}"#),
            AuthCheckOutcome::Revoke
        );
    }

    #[test]
    fn check_interval_is_at_most_60s() {
        assert!(CHECK_INTERVAL.as_secs() <= 60);
        assert_eq!(CHECK_INTERVAL, Duration::from_secs(30));
        assert_eq!(CHECK_INTERVAL_OFFLINE, Duration::from_secs(10));
        assert_eq!(CONFIRM_TTL, Duration::from_secs(60));
        assert!(CHECK_INTERVAL_OFFLINE < CHECK_INTERVAL);
        assert!(CHECK_INTERVAL_OFFLINE.as_secs() < CONFIRM_TTL.as_secs());
    }

    #[test]
    fn poll_interval_offline_is_faster() {
        LAST_API_OK.store(true, Ordering::SeqCst);
        assert_eq!(poll_interval(), CHECK_INTERVAL);
        LAST_API_OK.store(false, Ordering::SeqCst);
        assert_eq!(poll_interval(), CHECK_INTERVAL_OFFLINE);
    }

    #[test]
    fn confirm_ttl_is_not_24h() {
        assert_ne!(CONFIRM_TTL, Duration::from_secs(24 * 60 * 60));
        assert_eq!(CONFIRM_TTL, Duration::from_secs(60));
    }
}
