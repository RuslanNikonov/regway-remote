# Expected hbbs public key (ed25519, base64). This value is public, not a secret.
# Fingerprint helpers never print the full key: sha256 + first/last 4 chars only.
EXPECTED_HBBS_PUB_KEY='m1cfgCq297RvqqSGmC9PJvpcOWS+DL+WupiSQrXb2SU='

hbbs_key_fingerprint() {
  python3 -c '
import hashlib, sys
k = sys.argv[1]
h = hashlib.sha256(k.encode("utf-8")).hexdigest()
pre = k[:4] if len(k) >= 4 else k
suf = k[-4:] if len(k) >= 4 else k
print("sha256=%s prefix=%s suffix=%s len=%d" % (h, pre, suf, len(k)))
' "$1"
}
