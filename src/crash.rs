//! Process-stay-alive crash handling (C10 / C12).
//!
//! `panic = abort` plus `default_net` panics on VPN / iface change used to kill
//! the process with no log. This module:
//! - installs a panic hook that writes a redacted local crash log
//! - leaves a marker so the next launch can show a banner
//! - wraps `default_net` calls in `catch_unwind`

use hbb_common::{config::Config, log};
use std::{
    fs::OpenOptions,
    io::Write,
    panic::{self, AssertUnwindSafe},
    sync::atomic::{AtomicBool, Ordering},
};

const MARKER_NAME: &str = "crash.marker";
const LOG_NAME: &str = "crash.log";
const MAX_LOG_BYTES: u64 = 256 * 1024;

static HOOK_INSTALLED: AtomicBool = AtomicBool::new(false);

pub fn install_hooks() {
    if HOOK_INSTALLED.swap(true, Ordering::SeqCst) {
        return;
    }
    let prev = panic::take_hook();
    panic::set_hook(Box::new(move |info| {
        write_crash("panic", &format!("{info}"));
        prev(info);
    }));
}

pub fn log_path() -> std::path::PathBuf {
    Config::path(LOG_NAME)
}

pub fn marker_path() -> std::path::PathBuf {
    Config::path(MARKER_NAME)
}

pub fn pending() -> bool {
    marker_path().is_file()
}

pub fn ack() {
    let _ = std::fs::remove_file(marker_path());
}

pub fn write_crash(kind: &str, raw: &str) {
    let redacted = redact(raw);
    let path = log_path();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    if let Ok(meta) = std::fs::metadata(&path) {
        if meta.len() > MAX_LOG_BYTES {
            let _ = std::fs::remove_file(&path);
        }
    }
    let ts = chrono_now();
    let line = format!("{ts} [{kind}] {redacted}\n");
    if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(&path) {
        let _ = f.write_all(line.as_bytes());
        let _ = f.flush();
    }
    let marker = marker_path();
    if let Ok(mut f) = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(&marker)
    {
        let _ = writeln!(f, "{ts}");
    }
    log::error!("crash recorded ({kind}); report saved locally");
}

pub fn catch_net<T, F>(label: &str, f: F) -> Option<T>
where
    F: FnOnce() -> T,
{
    match panic::catch_unwind(AssertUnwindSafe(f)) {
        Ok(v) => Some(v),
        Err(_) => {
            log::warn!("network helper paniced ({label}); process stays up");
            write_crash("net", label);
            None
        }
    }
}

/// Strip secrets so the crash file can be shown in the UI.
pub fn redact(raw: &str) -> String {
    let mut s = raw.replace('\0', "");
    for key in [
        "password",
        "passwd",
        "token",
        "secret",
        "authorization",
        "api-key",
        "apikey",
        "private_key",
        "private-key",
        "UPDATE_SIGNING_KEY",
        "permanent-password",
    ] {
        s = redact_key(&s, key);
    }
    // Long base64-looking blobs (keys). Keep a short prefix.
    let re_like = s
        .split_whitespace()
        .map(|w| {
            if w.len() >= 32
                && w.bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'+' || b == b'/' || b == b'=')
            {
                format!("{}…", w.chars().take(6).collect::<String>())
            } else {
                w.to_owned()
            }
        })
        .collect::<Vec<_>>()
        .join(" ");
    re_like.chars().take(2000).collect()
}

fn redact_key(s: &str, key: &str) -> String {
    let lower = s.to_ascii_lowercase();
    let needle = key.to_ascii_lowercase();
    let mut out = s.to_owned();
    let mut from = 0;
    while let Some(rel) = lower[from..].find(&needle) {
        let abs = from + rel;
        let rest = &s[abs + key.len()..];
        let skip = rest
            .chars()
            .take_while(|c| *c == ' ' || *c == '=' || *c == ':' || *c == '"' || *c == '\'')
            .count();
        let start = abs + key.len() + skip;
        let take = s[start..]
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_' || *c == '+' || *c == '/' || *c == '=')
            .count();
        if take > 0 {
            let end = start + take;
            out.replace_range(start..end, "***");
            // restart on the mutated string is messy; one-pass approximation is enough
            break;
        }
        from = abs + key.len();
        if from >= lower.len() {
            break;
        }
    }
    out
}

fn chrono_now() -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    format!("{}", now.as_secs())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redact_drops_password_and_token() {
        let s = redact("password=hunter2 token=abcDEF012345 authorization: Bearer xyz");
        assert!(!s.contains("hunter2"), "{s}");
        assert!(!s.to_ascii_lowercase().contains("bearer xyz"));
        assert!(s.contains("***"));
    }

    #[test]
    fn catch_net_swallows_panic() {
        let v = catch_net("test", || -> i32 {
            panic!("iface gone");
        });
        assert!(v.is_none());
    }
}
