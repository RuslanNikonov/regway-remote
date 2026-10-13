#!/usr/bin/env python3
"""Build and ed25519-sign updates/manifest.json for RegWay Remote.

Reads UPDATE_SIGNING_KEY from the environment: a PKCS8 Ed25519 PEM, a
base64 32-byte seed, or a base64 64-byte secret key. Never prints the key.
Exits non-zero if the secret is missing or signing fails.
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import sys
from pathlib import Path


KEY_ID = "rw-2026-1"
PUBKEY_B64 = "8P4Zy7j96xjs3ObdDhOpUR6VQlxMCMeq73yzZwUv8RM="


def fail(msg: str) -> None:
    print(f"FAIL {msg}", file=sys.stderr)
    sys.exit(1)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


# PKCS8 Ed25519: SEQUENCE { version, AlgorithmIdentifier(OID 1.3.101.112), OCTET STRING { OCTET STRING seed } }
_ED25519_PKCS8_PREFIX = bytes.fromhex("302e020100300506032b657004220420")


def _seed_from_material(key: bytes) -> bytes:
    if key.startswith(_ED25519_PKCS8_PREFIX) and len(key) == len(_ED25519_PKCS8_PREFIX) + 32:
        return key[-32:]
    if len(key) == 64:
        return key[:32]
    if len(key) == 32:
        return key
    fail(
        "UPDATE_SIGNING_KEY must be a 32-byte seed, a 64-byte secret key, "
        "or a PKCS8 Ed25519 PEM"
    )
    return b""  # unreachable


def load_secret() -> bytes:
    raw = os.environ.get("UPDATE_SIGNING_KEY", "")
    # Do not log the value. Treat whitespace-only as missing.
    if not raw or not raw.strip():
        fail("UPDATE_SIGNING_KEY is not set")
    text = raw.strip()
    if "BEGIN" in text and "PRIVATE KEY" in text:
        body = "".join(
            line.strip() for line in text.splitlines() if "-----" not in line and line.strip()
        )
        try:
            der = base64.b64decode(body, validate=False)
        except Exception:
            fail("UPDATE_SIGNING_KEY PEM is not valid base64")
        return _seed_from_material(der)
    try:
        key = base64.b64decode(text, validate=False)
    except Exception:
        fail("UPDATE_SIGNING_KEY is not valid base64")
    return _seed_from_material(key)


def assert_client_pubkey(seed: bytes) -> None:
    """Refuse to publish a manifest the installed client cannot verify."""
    pub = ""
    try:
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric.ed25519 import (
            Ed25519PrivateKey,
        )

        raw = (
            Ed25519PrivateKey.from_private_bytes(seed)
            .public_key()
            .public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        )
        pub = base64.b64encode(raw).decode("ascii")
    except ImportError:
        try:
            from nacl.signing import SigningKey

            pub = base64.b64encode(bytes(SigningKey(seed).verify_key)).decode("ascii")
        except ImportError:
            return
    if pub != PUBKEY_B64:
        fail("UPDATE_SIGNING_KEY does not match the client public key")


def sign_ed25519(seed: bytes, message: bytes) -> bytes:
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import (
            Ed25519PrivateKey,
        )

        return Ed25519PrivateKey.from_private_bytes(seed).sign(message)
    except ImportError:
        pass
    try:
        from nacl.signing import SigningKey

        return SigningKey(seed).sign(message).signature
    except ImportError:
        fail("need the 'cryptography' or 'pynacl' Python package to sign")
    return b""


def collect_files(root: Path) -> list[dict]:
    mapping = [
        ("windows", "x86_64", "RegWayRemote-*-x86_64.exe"),
        ("windows", "x86_64", "RegWayRemote-*-x86_64.msi"),
        ("macos", "x86_64", "RegWayRemote-*-x86_64.dmg"),
        ("macos", "aarch64", "RegWayRemote-*-aarch64.dmg"),
    ]
    files: list[dict] = []
    seen: set[str] = set()
    for os_name, arch, pattern in mapping:
        matches = sorted(root.rglob(pattern))
        matches = [p for p in matches if p.is_file() and p.name != "SHA256SUMS"]
        if not matches:
            continue
        path = matches[0]
        if path.name in seen:
            continue
        seen.add(path.name)
        files.append(
            {
                "os": os_name,
                "arch": arch,
                "url": f"https://remote.regway.group/updates/{path.name}",
                "sha256": sha256_file(path),
                "size": path.stat().st_size,
                "filename": path.name,
            }
        )
    if not files:
        fail(f"no candidate artifacts under {root}")
    return files


def main() -> None:
    if len(sys.argv) < 2:
        fail("usage: sign-update-manifest.py <artifacts-dir> [out-dir]")
    root = Path(sys.argv[1]).resolve()
    out = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else root / "updates"
    out.mkdir(parents=True, exist_ok=True)

    seed = load_secret()
    assert_client_pubkey(seed)
    version = os.environ.get("VERSION", "1.5.0")
    try:
        sequence = int(os.environ.get("UPDATE_SEQUENCE") or os.environ.get("GITHUB_RUN_NUMBER") or "1")
    except ValueError:
        fail("UPDATE_SEQUENCE / GITHUB_RUN_NUMBER is not an integer")

    manifest = {
        "version": version,
        "sequence": sequence,
        "key_id": KEY_ID,
        "rollback_allowed": True,
        "notes": os.environ.get("UPDATE_NOTES", "RegWay Remote candidate build"),
        "files": collect_files(root),
    }
    body = (json.dumps(manifest, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    sig = sign_ed25519(seed, body)
    sig_b64 = base64.b64encode(sig).decode("ascii")

    man_path = out / "manifest.json"
    sig_path = out / "manifest.json.sig"
    man_path.write_bytes(body)
    sig_path.write_text(sig_b64 + "\n", encoding="ascii")

    print("===== manifest.json =====")
    print(body.decode("utf-8"), end="" if body.endswith(b"\n") else "\n")
    print("===== manifest.json.sig =====")
    print(sig_b64)
    print("===== sha256sum =====")
    for p in (man_path, sig_path):
        digest = sha256_file(p)
        print(f"{digest}  {p.name}")
    print("===== signed =====")
    print(f"key_id={KEY_ID} pubkey={PUBKEY_B64} files={len(manifest['files'])} sequence={sequence}")
    print("OK signed manifest.json")


if __name__ == "__main__":
    main()
