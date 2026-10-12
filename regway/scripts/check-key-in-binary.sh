#!/usr/bin/env bash
# Fail unless the expected hbbs public key bytes are present in a built binary
# or .app bundle. Logs paths that matched; never prints the key itself.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hbbs-key.sh
source "$HERE/scripts/hbbs-key.sh"

if [ $# -lt 1 ]; then
  echo "usage: $0 <file-or-dir> [file-or-dir...]" >&2
  exit 2
fi

export EXPECTED_HBBS_PUB_KEY
python3 - "$EXPECTED_HBBS_PUB_KEY" "$@" <<'PY'
import os, sys, pathlib
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

expected = sys.argv[1]
needle = expected.encode("ascii")
skip_ext = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".icns", ".ico", ".svg",
    ".nib", ".car", ".plist", ".strings", ".json", ".txt", ".md", ".html",
    ".dmg", ".bmp", ".ttf", ".otf", ".woff", ".woff2",
}
hits = []
missed = []
for arg in sys.argv[2:]:
    root = pathlib.Path(arg)
    if not root.exists():
        print(f"FAIL path does not exist: {root}", file=sys.stderr)
        sys.exit(1)
    files = [root] if root.is_file() else [p for p in root.rglob("*") if p.is_file()]
    found_here = False
    for p in files:
        if p.suffix.lower() in skip_ext:
            continue
        try:
            data = p.read_bytes()
        except OSError:
            continue
        if needle in data:
            hits.append(str(p))
            found_here = True
    if not found_here:
        missed.append(str(root))

fp = os.environ.get("HBBS_KEY_FP", "")
if missed:
    print("FAIL expected hbbs public key not found in:", *missed, sep="\n  ", file=sys.stderr)
    print("  Compare RS_PUB_KEY fingerprint with expected (sha256 / prefix+suffix).", file=sys.stderr)
    print("  The GitHub secret cannot be changed from this script.", file=sys.stderr)
    sys.exit(1)
for h in hits:
    print(f"OK   key bytes present in {h}")
print("OK   expected hbbs public key is in the built binary")
PY
