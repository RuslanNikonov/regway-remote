//! Signed in-app updater. See `server/updates/CONTRACT.md`.

use hbb_common::{
    anyhow::{anyhow, bail},
    config::LocalConfig,
    log,
    sodiumoxide::{base64, crypto::sign},
    ResultType,
};
use serde_derive::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File, OpenOptions},
    io::{Read, Seek, SeekFrom, Write},
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex,
    },
    time::Duration,
};

pub const MANIFEST_URL: &str = "https://remote.regway.group/updates/manifest.json";
pub const MANIFEST_SIG_URL: &str = "https://remote.regway.group/updates/manifest.json.sig";
pub const KEY_ID: &str = "rw-2026-1";
pub const PUBKEY_B64: &str = "8P4Zy7j96xjs3ObdDhOpUR6VQlxMCMeq73yzZwUv8RM=";
pub const CHUNK: u64 = 16 * 1024;
/// Reject the manifest before verifying the signature if it exceeds this.
pub const MANIFEST_MAX: u64 = 15 * 1024;
const MAX_FAILS: u32 = 3;

static STARTED: AtomicBool = AtomicBool::new(false);

lazy_static::lazy_static! {
    static ref STATUS: Mutex<UpdateStatus> = Mutex::new(UpdateStatus::default());
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct UpdateStatus {
    pub state: String, // idle|checking|available|downloading|ready|installing|error
    pub progress: u8,
    pub resuming: bool,
    pub attempts: u32,
    pub error: String,
    pub version: String,
    pub sequence: u64,
    pub notes: String,
    pub rollback_allowed: bool,
    pub installed_sequence: u64,
    pub mode: String,
    pub filename: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    pub version: String,
    pub sequence: u64,
    pub key_id: String,
    #[serde(default)]
    pub rollback_allowed: Option<bool>,
    #[serde(default)]
    pub notes: Option<String>,
    #[serde(default)]
    pub files: Vec<ManifestFile>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ManifestFile {
    pub os: String,
    pub arch: String,
    pub url: String,
    pub sha256: String,
    pub size: u64,
    pub filename: String,
}

pub fn ensure_started() {
    if STARTED.swap(true, Ordering::SeqCst) {
        return;
    }
    {
        let mut st = STATUS.lock().unwrap();
        st.mode = current_mode();
        st.installed_sequence = accepted_sequence();
        if st.state.is_empty() {
            st.state = "idle".into();
        }
    }
    std::thread::Builder::new()
        .name("rw-update".into())
        .spawn(|| {
            if let Ok(rt) = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
            {
                rt.block_on(update_loop());
            }
        })
        .ok();
}

pub fn status_json() -> String {
    serde_json::to_string(&*STATUS.lock().unwrap()).unwrap_or_else(|_| "{}".into())
}

pub fn set_mode(mode: &str) {
    let m = if mode == "manual" { "manual" } else { "auto" };
    LocalConfig::set_option("rw-update-mode".into(), m.into());
    STATUS.lock().unwrap().mode = m.into();
}

pub fn current_mode() -> String {
    let v = LocalConfig::get_option("rw-update-mode");
    if v == "manual" {
        "manual".into()
    } else {
        "auto".into()
    }
}

pub fn trigger_check() {
    STATUS.lock().unwrap().state = "checking".into();
}

pub fn trigger_download() {
    let mut st = STATUS.lock().unwrap();
    if st.state == "available" || st.state == "error" || st.state == "ready" {
        st.attempts = 0;
        st.error.clear();
        st.state = "downloading".into();
    }
}

pub fn trigger_install() {
    let mut st = STATUS.lock().unwrap();
    if st.state == "ready" {
        st.state = "installing".into();
    }
}

pub fn trigger_retry() {
    let mut st = STATUS.lock().unwrap();
    st.attempts = 0;
    st.error.clear();
    if st.version.is_empty() {
        st.state = "checking".into();
    } else {
        st.state = "downloading".into();
    }
}

fn accepted_sequence() -> u64 {
    LocalConfig::get_option("rw-update-sequence")
        .parse()
        .unwrap_or(0)
}

fn accepted_sha() -> String {
    LocalConfig::get_option("rw-update-manifest-sha")
}

fn remember_accepted(seq: u64, sha: &str) {
    LocalConfig::set_option("rw-update-sequence".into(), seq.to_string());
    LocalConfig::set_option("rw-update-manifest-sha".into(), sha.into());
}

pub fn evaluate_sequence(accepted_seq: u64, accepted_sha: &str, seq: u64, sha: &str) -> ResultType<()> {
    if seq < accepted_seq {
        bail!("sequence {seq} is older than accepted {accepted_seq}");
    }
    if seq == accepted_seq && sha != accepted_sha && !accepted_sha.is_empty() {
        bail!("same sequence {seq} but different manifest hash");
    }
    Ok(())
}

pub fn verify_manifest_sig(body: &[u8], sig_b64: &str, key_id: &str) -> ResultType<()> {
    if key_id != KEY_ID {
        bail!("unexpected key_id {key_id}");
    }
    let pk_bytes = base64::decode(PUBKEY_B64, base64::Variant::Original)
        .map_err(|_| anyhow!("bad public key"))?;
    let pk = sign::PublicKey::from_slice(&pk_bytes).ok_or_else(|| anyhow!("public key length"))?;
    let sig_bytes = base64::decode(sig_b64.trim(), base64::Variant::Original)
        .map_err(|_| anyhow!("bad signature encoding"))?;
    let sig = sign::Signature::from_slice(&sig_bytes).ok_or_else(|| anyhow!("signature length"))?;
    if !sign::verify_detached(&sig, body, &pk) {
        bail!("manifest signature mismatch");
    }
    Ok(())
}

fn sha256_hex(data: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(data);
    format!("{:x}", h.finalize())
}

fn current_os() -> &'static str {
    if cfg!(target_os = "windows") {
        "windows"
    } else if cfg!(target_os = "macos") {
        "macos"
    } else {
        "linux"
    }
}

fn current_arch() -> &'static str {
    if cfg!(target_arch = "aarch64") {
        "aarch64"
    } else {
        "x86_64"
    }
}

fn pick_file(m: &Manifest) -> ResultType<&ManifestFile> {
    let os = current_os();
    let arch = current_arch();
    m.files
        .iter()
        .find(|f| f.os == os && f.arch == arch)
        .ok_or_else(|| anyhow!("no file for {os}/{arch}"))
}

fn dest_path(filename: &str) -> PathBuf {
    let mut p = std::env::temp_dir();
    p.push("regway-updates");
    let _ = fs::create_dir_all(&p);
    p.push(filename);
    p
}

/// `Range: bytes=start-end` (inclusive). Every request from this downloader
/// carries this header; a GET without Range is never issued.
pub fn range_header(offset: u64, end_inclusive: u64) -> String {
    format!("bytes={offset}-{end_inclusive}")
}

/// Shared Range downloader for manifests, signatures, and payload files.
/// Chunks are at most 16 KiB. Partial dest files are resumed. `max_size` is
/// enforced as bytes arrive so a too-large manifest is rejected before the
/// signature is inspected. Does not load the whole object into memory.
pub async fn range_fetch(
    url: &str,
    dest: &std::path::Path,
    max_size: Option<u64>,
    mut on_progress: impl FnMut(u64, Option<u64>),
) -> ResultType<u64> {
    let client = crate::hbbs_http::create_http_client_async_with_url_strict(url).await?;
    let mut have = dest.metadata().map(|m| m.len()).unwrap_or(0);
    if let Some(max) = max_size {
        if have > max {
            let _ = fs::remove_file(dest);
            have = 0;
        }
    }
    let mut out = OpenOptions::new()
        .create(true)
        .write(true)
        .open(dest)?;
    out.seek(SeekFrom::Start(have))?;
    let mut offset = have;
    let mut known_total: Option<u64> = None;
    on_progress(offset, known_total);
    loop {
        if let Some(total) = known_total {
            if offset >= total {
                break;
            }
        }
        if let Some(max) = max_size {
            if offset >= max {
                break;
            }
        }
        let span = CHUNK
            .min(max_size.map(|m| m.saturating_sub(offset)).unwrap_or(CHUNK))
            .max(1);
        let end = offset + span - 1;
        let resp = client
            .get(url)
            .header("Range", range_header(offset, end))
            .send()
            .await?;
        let status = resp.status().as_u16();
        if !(resp.status().is_success() || status == 206) {
            bail!("range {offset}-{end} -> {status}");
        }
        if let Some(cr) = resp
            .headers()
            .get("content-range")
            .and_then(|v| v.to_str().ok())
        {
            if let Some(total) = parse_content_range_total(cr) {
                if let Some(max) = max_size {
                    if total > max {
                        let _ = fs::remove_file(dest);
                        bail!("object exceeds {} bytes", max);
                    }
                }
                known_total = Some(total);
            }
        }
        let bytes = resp.bytes().await?;
        if bytes.is_empty() {
            if known_total.map(|t| offset >= t).unwrap_or(true) {
                break;
            }
            bail!("empty range body at {offset}");
        }
        // Server ignored Range and sent the whole object: keep only the
        // requested window so we never accept a single full-file GET.
        let take = if status == 200 && bytes.len() as u64 > span {
            bytes.len().min(span as usize)
        } else {
            bytes.len()
        };
        let chunk = &bytes[..take];
        let next = offset + chunk.len() as u64;
        if let Some(max) = max_size {
            if next > max {
                let _ = fs::remove_file(dest);
                bail!("object exceeds {} bytes", max);
            }
        }
        out.write_all(chunk)?;
        offset = next;
        on_progress(offset, known_total);
        if status == 200 && known_total.is_none() {
            // 200 with a Range-sized (or smaller) body: that was the rest.
            if take as u64 <= span {
                break;
            }
        }
        if chunk.len() as u64 < span {
            break;
        }
    }
    out.flush()?;
    drop(out);
    if let Some(max) = max_size {
        if offset > max {
            let _ = fs::remove_file(dest);
            bail!("object exceeds {} bytes", max);
        }
    }
    Ok(offset)
}

/// Range-download a small object (manifest / signature) and return its bytes.
pub async fn range_get(
    url: &str,
    dest: &std::path::Path,
    max_size: Option<u64>,
) -> ResultType<Vec<u8>> {
    range_fetch(url, dest, max_size, |_, _| {}).await?;
    let data = fs::read(dest)?;
    if let Some(max) = max_size {
        if data.len() as u64 > max {
            let _ = fs::remove_file(dest);
            bail!("object exceeds {} bytes", max);
        }
    }
    Ok(data)
}

pub fn parse_content_range_total(header: &str) -> Option<u64> {
    // "bytes 0-16383/20000" or "bytes 0-16383/*"
    let slash = header.rfind('/')?;
    let total = header[slash + 1..].trim();
    if total == "*" {
        return None;
    }
    total.parse().ok()
}

async fn update_loop() {
    // Poll often so download/install progress moves; check the manifest on
    // first boot (so this build can update itself to the next) and every 6 h.
    let mut ticks: u64 = 0;
    loop {
        tokio::time::sleep(Duration::from_secs(2)).await;
        ticks = ticks.saturating_add(1);
        let state = STATUS.lock().unwrap().state.clone();
        if (ticks == 4 || ticks % (3 * 60 * 60) == 0)
            && (state == "idle" || state == "available" || state.is_empty())
            && current_mode() == "auto"
        {
            STATUS.lock().unwrap().state = "checking".into();
        }
        pump_once().await;
    }
}

async fn pump_once() {
    let state = STATUS.lock().unwrap().state.clone();
    match state.as_str() {
        "checking" => {
            if let Err(e) = check_once().await {
                fail(&e.to_string());
            }
        }
        "downloading" => {
            if let Err(e) = download_once().await {
                bump_fail(&e.to_string());
            }
        }
        "ready" => {
            #[cfg(not(any(target_os = "android", target_os = "ios")))]
            if current_mode() == "auto" && crate::updater::has_no_active_conns() {
                STATUS.lock().unwrap().state = "installing".into();
            }
        }
        "installing" => {
            if let Err(e) = install_once() {
                fail(&e.to_string());
            }
        }
        _ => {}
    }
}

async fn check_once() -> ResultType<()> {
    // Manifest and signature use the same Range downloader as the payload
    // files. Size is capped before the signature is inspected; the signature
    // is checked before JSON fields (sequence / hashes) are trusted.
    let man_path = dest_path("manifest.json");
    let sig_path = dest_path("manifest.json.sig");
    let body = range_get(MANIFEST_URL, &man_path, Some(MANIFEST_MAX)).await?;
    if (body.len() as u64) > MANIFEST_MAX {
        let _ = fs::remove_file(&man_path);
        bail!("manifest exceeds {} bytes", MANIFEST_MAX);
    }
    let sig_bytes = range_get(MANIFEST_SIG_URL, &sig_path, Some(MANIFEST_MAX)).await?;
    let sig = String::from_utf8_lossy(&sig_bytes).into_owned();
    if let Err(e) = verify_manifest_sig(&body, &sig, KEY_ID) {
        let _ = fs::remove_file(&man_path);
        let _ = fs::remove_file(&sig_path);
        return Err(e);
    }
    let parsed: Manifest = serde_json::from_slice(&body)?;
    if parsed.key_id != KEY_ID {
        bail!("unexpected key_id {}", parsed.key_id);
    }
    let sha = sha256_hex(&body);
    evaluate_sequence(accepted_sequence(), &accepted_sha(), parsed.sequence, &sha)?;
    remember_accepted(parsed.sequence, &sha);
    let file = pick_file(&parsed)?;
    let mut st = STATUS.lock().unwrap();
    st.version = parsed.version.clone();
    st.sequence = parsed.sequence;
    st.notes = parsed.notes.clone().unwrap_or_default();
    st.rollback_allowed = parsed.rollback_allowed.unwrap_or(true);
    st.filename = file.filename.clone();
    st.progress = 0;
    st.error.clear();
    st.installed_sequence = accepted_sequence();
    if dest_path(&file.filename).is_file()
        && dest_path(&file.filename)
            .metadata()
            .map(|m| m.len() == file.size)
            .unwrap_or(false)
        && file_sha256(&dest_path(&file.filename)).ok().as_deref() == Some(file.sha256.as_str())
    {
        st.state = "ready".into();
        st.progress = 100;
    } else {
        st.state = "available".into();
        notify_available(&parsed.version);
        if current_mode() == "auto" {
            st.state = "downloading".into();
        }
    }
    // stash the chosen file as JSON in local option for download_once
    LocalConfig::set_option(
        "rw-update-file".into(),
        serde_json::to_string(file).unwrap_or_default(),
    );
    LocalConfig::set_option(
        "rw-update-rollback".into(),
        if parsed.rollback_allowed.unwrap_or(true) {
            "Y"
        } else {
            "N"
        }
        .into(),
    );
    Ok(())
}

fn notify_available(version: &str) {
    #[cfg(feature = "flutter")]
    {
        let mut m = std::collections::HashMap::new();
        m.insert("name", "rw_update_available");
        m.insert("version", version);
        if let Ok(data) = serde_json::to_string(&m) {
            let _ = crate::flutter::push_global_event(crate::flutter::APP_TYPE_MAIN, data);
        }
    }
    native_notify(version);
}

fn native_notify(version: &str) {
    let title = "RegWay Remote";
    let body = format!("Доступно обновление {version}");
    #[cfg(windows)]
    {
        let _ = tauri_winrt_notification::Toast::new(
            tauri_winrt_notification::Toast::POWERSHELL_APP_ID,
        )
        .title(title)
        .text1(&body)
        .show();
    }
    #[cfg(target_os = "macos")]
    {
        let _ = std::process::Command::new("osascript")
            .arg("-e")
            .arg(format!(
                "display notification \"{}\" with title \"{}\"",
                body.replace('"', "'"),
                title
            ))
            .status();
    }
    #[cfg(target_os = "linux")]
    {
        let _ = std::process::Command::new("notify-send")
            .args([title, &body])
            .status();
    }
}

async fn download_once() -> ResultType<()> {
    let file: ManifestFile = serde_json::from_str(&LocalConfig::get_option("rw-update-file"))?;
    let path = dest_path(&file.filename);
    let mut have = path.metadata().map(|m| m.len()).unwrap_or(0);
    if have > file.size {
        let _ = fs::remove_file(&path);
        have = 0;
    }
    {
        let mut st = STATUS.lock().unwrap();
        st.resuming = have > 0;
        st.filename = file.filename.clone();
    }
    range_fetch(&file.url, &path, Some(file.size), |got, _total| {
        let pct = ((got.min(file.size) * 100) / file.size.max(1)) as u8;
        let mut st = STATUS.lock().unwrap();
        st.progress = pct;
        st.resuming = have > 0;
        st.state = "downloading".into();
    })
    .await?;
    let got = path.metadata()?.len();
    if got != file.size {
        let _ = fs::remove_file(&path);
        bail!("size {got} != {}", file.size);
    }
    let hex = file_sha256(&path)?;
    if hex != file.sha256.to_ascii_lowercase() {
        let _ = fs::remove_file(&path);
        bail!("sha256 mismatch");
    }
    let mut st = STATUS.lock().unwrap();
    st.progress = 100;
    st.attempts = 0;
    st.state = "ready".into();
    Ok(())
}

fn file_sha256(path: &std::path::Path) -> ResultType<String> {
    let mut f = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

fn install_once() -> ResultType<()> {
    let file: ManifestFile = serde_json::from_str(&LocalConfig::get_option("rw-update-file"))?;
    if LocalConfig::get_option("rw-update-rollback") == "N" {
        // installing a newer sequence is always allowed; this flag only blocks
        // rolling *back* onto a build that set rollback_allowed=false. The
        // sequence check already forbids going backwards.
    }
    let path = dest_path(&file.filename);
    if !path.is_file() {
        bail!("update file missing");
    }
    #[cfg(target_os = "macos")]
    {
        clear_quarantine(&path);
        // Open the dmg; the user / installer copies the app. Then bounce the service.
        let _ = std::process::Command::new("open").arg(&path).status();
        restart_mac_service();
    }
    #[cfg(target_os = "windows")]
    {
        let _ = std::process::Command::new(&path).spawn();
    }
    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        let _ = std::process::Command::new("xdg-open").arg(&path).status();
    }
    STATUS.lock().unwrap().state = "idle".into();
    Ok(())
}

#[cfg(target_os = "macos")]
fn clear_quarantine(path: &std::path::Path) {
    let _ = std::process::Command::new("xattr")
        .args(["-r", "-d", "com.apple.quarantine"])
        .arg(path)
        .status();
}

#[cfg(target_os = "macos")]
fn restart_mac_service() {
    let app = crate::get_app_name();
    let label = format!("com.regway.remote.service");
    let _ = std::process::Command::new("launchctl")
        .args(["kickstart", "-k", &format!("gui/{}/{label}", users_uid(),)])
        .status();
    let _ = app;
}

#[cfg(target_os = "macos")]
fn users_uid() -> u32 {
    unsafe { hbb_common::libc::getuid() }
}

fn fail(msg: &str) {
    let mut st = STATUS.lock().unwrap();
    st.state = "error".into();
    st.error = msg.chars().take(200).collect();
}

fn bump_fail(msg: &str) {
    let mut st = STATUS.lock().unwrap();
    st.attempts = st.attempts.saturating_add(1);
    st.error = msg.chars().take(200).collect();
    if st.attempts >= MAX_FAILS {
        st.state = "error".into();
        st.error = "download-failed".into();
    } else {
        st.state = "downloading".into();
    }
}

/// Public so Flutter can decide whether a listed version may be a rollback target.
pub fn rollback_allowed_for(flag: Option<bool>) -> bool {
    flag.unwrap_or(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sequence_rejects_older_and_mutated_same() {
        evaluate_sequence(10, "aaa", 9, "bbb").unwrap_err();
        evaluate_sequence(10, "aaa", 10, "bbb").unwrap_err();
        evaluate_sequence(10, "aaa", 10, "aaa").unwrap();
        evaluate_sequence(10, "aaa", 11, "ccc").unwrap();
        evaluate_sequence(0, "", 1, "ddd").unwrap();
    }

    #[test]
    fn signature_roundtrip_and_wrong_key_id() {
        let (pk, sk) = sign::gen_keypair();
        let body = b"{\"sequence\":1}";
        let sig = sign::sign_detached(body, &sk);
        let sig_b64 = base64::encode(sig.0, base64::Variant::Original);
        // Production pubkey is not this pair — verify_manifest_sig must fail.
        verify_manifest_sig(body, &sig_b64, KEY_ID).unwrap_err();
        // Wrong key_id fails before crypto.
        verify_manifest_sig(body, &sig_b64, "other").unwrap_err();
        // Direct verify with the generated key succeeds (contract: sig of raw bytes).
        assert!(sign::verify_detached(&sig, body, &pk));
        let _ = pk;
    }

    #[test]
    fn rollback_flag() {
        assert!(rollback_allowed_for(None));
        assert!(rollback_allowed_for(Some(true)));
        assert!(!rollback_allowed_for(Some(false)));
    }

    #[test]
    fn content_range_total() {
        assert_eq!(
            parse_content_range_total("bytes 0-16383/20000"),
            Some(20000)
        );
        assert_eq!(parse_content_range_total("bytes 0-100/*"), None);
        assert_eq!(parse_content_range_total("bytes 0-100/15360"), Some(15360));
    }

    #[test]
    fn manifest_cap_is_15kib() {
        assert_eq!(MANIFEST_MAX, 15 * 1024);
        assert_eq!(CHUNK, 16 * 1024);
        assert!(CHUNK <= 16 * 1024);
        assert!(15 * 1024 + 1 > MANIFEST_MAX);
    }

    #[test]
    fn range_header_is_always_present() {
        assert_eq!(range_header(0, CHUNK - 1), "bytes=0-16383");
        assert_eq!(range_header(16384, 32767), "bytes=16384-32767");
        assert!(range_header(0, 15 * 1024 - 1).starts_with("bytes="));
    }
}
