//! Mandatory account login gate for RegWay Remote.
//!
//! Incoming and outgoing sessions are refused unless a rustdesk-api access token
//! is present and has been validated against `/api/currentUser` within
//! [`OFFLINE_GRACE`]. The same check runs in the UI process and in `--server`.
//!
//! Verified rustdesk-api behaviour:
//! - a disabled user's existing token on `POST /api/currentUser` → HTTP 401
//!   `{"error":"Unauthorized"}` → [`AuthCheckOutcome::Revoke`]
//! - `POST /api/login` for a disabled user → HTTP 400 `{"error":"UserDisabled"}`
//!   (shown on the Flutter gate; not this heartbeat)
//! - a transport / network error is **not** a 401 → [`AuthCheckOutcome::Grace`]

use hbb_common::{
    anyhow::anyhow,
    config::{Config, LocalConfig},
    log, tokio, ResultType,
};
use serde_json::{json, Value};
use std::sync::Once;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// If the API is unreachable, a token last validated within this window still
/// allows the session. After it expires the login screen is shown again.
pub const OFFLINE_GRACE: Duration = Duration::from_secs(24 * 60 * 60);

/// How often `/api/currentUser` is polled while a token is present.
/// Aim 30 s so a disable/delete in `/_admin/` drops every session within 60 s.
pub const CHECK_INTERVAL: Duration = Duration::from_secs(30);

pub const TOKEN_VALIDATED_AT: &str = "rw-token-validated-at";
pub const LOGIN_OK: &str = "rw-login-ok";
pub const LOGIN_TOKEN: &str = "rw-login-token";
/// `Y` after a successful `/api/currentUser`. `N` after a network timeout /
/// unreachable API (grace, not revoke). Empty when there is no token.
pub const API_REACHABLE: &str = "rw-api-reachable";
const ACCESS_TOKEN: &str = "access_token";

/// Result of one `/api/currentUser` (or equivalent) check. Pure: no I/O.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthCheckOutcome {
    /// Token is valid; refresh the grace timestamp.
    Allow,
    /// HTTP 401/403/400, disabled/deleted user, or an explicit error body.
    Revoke,
    /// Transport failure or unexpected HTTP. Keep the 24 h offline grace.
    Grace,
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

pub fn is_within_offline_grace() -> bool {
    match validated_at() {
        Some(ts) => unix_now().saturating_sub(ts) < OFFLINE_GRACE.as_secs(),
        None => false,
    }
}

/// Hot path: no network. Used by accept, connect, CLI, rendezvous.
pub fn is_session_allowed() -> bool {
    if access_token().is_empty() && Config::get_option(LOGIN_OK) != "Y" {
        return false;
    }
    is_within_offline_grace()
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

/// Map an HTTP status (or a transport error) plus body to allow / revoke / grace.
///
/// `status == None` is a network error (unreachable API, TLS, timeout). That is
/// not a 401: keep [`OFFLINE_GRACE`]. A disabled account's token is 401.
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
        Some(_) => AuthCheckOutcome::Grace,
        None => AuthCheckOutcome::Grace,
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

/// POST `/api/currentUser`. Updates the grace timestamp on success; revokes on
/// 401/disabled. Unreachable API keeps the session only inside [`OFFLINE_GRACE`].
pub async fn revalidate() -> ResultType<bool> {
    let token = access_token();
    if token.is_empty() {
        if Config::get_option(LOGIN_OK) == "Y" && !is_within_offline_grace() {
            revoke("no token and offline grace expired");
        }
        return Ok(false);
    }
    let api = crate::get_api_server(
        Config::get_option("api-server"),
        Config::get_option("custom-rendezvous-server"),
    );
    if api.is_empty() {
        return Ok(apply_outcome(AuthCheckOutcome::Grace, "no api-server"));
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
            // Timeout / DNS / TLS: not a 401. Stay inside OFFLINE_GRACE.
            log::warn!("login-gate: currentUser unreachable (network timeout/error, not 401): {err:?}");
            return Ok(apply_outcome(AuthCheckOutcome::Grace, "network timeout"));
        }
    };
    let outcome = decide_auth_check(status, &resp_body);
    let reason = match (status, outcome) {
        (Some(401), AuthCheckOutcome::Revoke) => "API 401 Unauthorized (disabled/deleted or invalid token)",
        (Some(403), AuthCheckOutcome::Revoke) => "API 403",
        (Some(400), AuthCheckOutcome::Revoke) => "API 400",
        (_, AuthCheckOutcome::Revoke) => "account disabled or deleted",
        (Some(s), AuthCheckOutcome::Grace) => {
            log::warn!("login-gate: currentUser HTTP {s}, applying offline grace");
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
        AuthCheckOutcome::Grace => {
            set_api_reachable(Some(false));
            let ok = is_within_offline_grace();
            if !ok {
                revoke("offline grace expired");
            }
            ok
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
                        tokio::time::sleep(CHECK_INTERVAL).await;
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
        assert_eq!(decide_auth_check(None, ""), AuthCheckOutcome::Grace);
    }

    #[test]
    fn timeout_does_not_revoke() {
        // post_request_with_status Err (timeout) is mapped to status=None.
        assert_eq!(
            decide_auth_check(None, "timed out"),
            AuthCheckOutcome::Grace
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
            AuthCheckOutcome::Grace
        );
        assert_eq!(
            decide_auth_check(Some(500), ""),
            AuthCheckOutcome::Grace
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
        assert_eq!(OFFLINE_GRACE, Duration::from_secs(24 * 60 * 60));
    }
}
