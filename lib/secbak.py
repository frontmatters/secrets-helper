"""secbak — the .secbak backup format for secrets-helper keychains.

Two modes:
  - default       : AES-256-GCM + scrypt + magic-as-AAD (authenticated, memory-hard)
  - openssl_compat: AES-256-CBC + PBKDF2 in OpenSSL's `Salted__` format (emergency
                    recovery without this tool)

Header (default mode, 36 bytes, then GCM ciphertext and tag):
  0..5  magic 'SECBAK' | 6 format_version | 7 kdf_id(1=scrypt) | 8..23 salt | 24..35 nonce
"""
import io
import os
import sys
import re
import json
import tarfile
import hashlib
import socket
import datetime

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes, padding

MAGIC = b"SECBAK"
FORMAT_VERSION = 1
KDF_SCRYPT = 1
SCRYPT_N, SCRYPT_R, SCRYPT_P = 2 ** 15, 8, 1
HEADER_LEN = 36

# OpenSSL compat (mode 2)
OPENSSL_MAGIC = b"Salted__"
OPENSSL_ITER = 100_000


class SecbakError(Exception):
    pass


class IntegrityError(SecbakError):
    """An unpacked database does not match its manifest checksum."""


class TargetExistsError(SecbakError):
    """The restore target already holds keychain files and force is False."""


# ── key derivation ────────────────────────────────────────────────────────────
def _scrypt_key(password, salt):
    return Scrypt(salt=salt, length=32, n=SCRYPT_N, r=SCRYPT_R, p=SCRYPT_P).derive(password)


def _openssl_key_iv(password, salt):
    dk = PBKDF2HMAC(algorithm=hashes.SHA256(), length=48, salt=salt,
                    iterations=OPENSSL_ITER).derive(password)
    return dk[:32], dk[32:48]


# ── archive building ──────────────────────────────────────────────────────────
# A keychain file name inside a backup: a plain file name, nothing that could
# point outside the restore directory (security review 2026-10-01, L2).
NAME_RE = re.compile(r"^[A-Za-z0-9._@:+-]+\.keychain-db$")


def _write_private(path, data):
    """Create the file with mode 600 from the start (open-then-chmod left it
    readable for a moment)."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.fchmod(fd, 0o600)
        os.write(fd, data if isinstance(data, bytes) else data.encode())
    finally:
        os.close(fd)


def _sha256(b):
    return hashlib.sha256(b).hexdigest()


def _read(path):
    with open(path, "rb") as fh:
        return fh.read()


def _build_tar(files):
    """Bouw (tar_bytes, manifest) uit een lijst bestandspaden."""
    blobs = {}
    for path in files:
        blobs[os.path.basename(path)] = _read(path)
    manifest = {
        "format_version": FORMAT_VERSION,
        "created": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "host": socket.gethostname(),
        "tool": "secrets-helper",
        "keychains": [{"name": n.replace(".keychain-db", ""), "file": n,
                       "bytes": len(d), "sha256": _sha256(d)} for n, d in blobs.items()],
        "note": "Laag 2: keychain-eigen wachtwoorden zitten NIET in deze backup. Apart borgen.",
    }
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as tar:
        mbytes = json.dumps(manifest, indent=2).encode()
        ti = tarfile.TarInfo("manifest.json"); ti.size = len(mbytes)
        tar.addfile(ti, io.BytesIO(mbytes))
        for name, data in blobs.items():
            ti = tarfile.TarInfo(name); ti.size = len(data)
            tar.addfile(ti, io.BytesIO(data))
    return buf.getvalue(), manifest


# ── pack ──────────────────────────────────────────────────────────────────────
def pack(files, out_path, password, openssl_compat=False):
    plaintext, manifest = _build_tar(files)
    if openssl_compat:
        salt = os.urandom(8)
        key, iv = _openssl_key_iv(password, salt)
        padder = padding.PKCS7(128).padder()
        padded = padder.update(plaintext) + padder.finalize()
        enc = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
        ct = enc.update(padded) + enc.finalize()
        blob = OPENSSL_MAGIC + salt + ct
        _write_private(out_path, blob)
        _write_private(out_path + ".sha256", f"{_sha256(blob)}  {os.path.basename(out_path)}\n")
    else:
        salt, nonce = os.urandom(16), os.urandom(12)
        header = MAGIC + bytes([FORMAT_VERSION, KDF_SCRYPT]) + salt + nonce
        key = _scrypt_key(password, salt)
        ct = AESGCM(key).encrypt(nonce, plaintext, header)
        _write_private(out_path, header + ct)
    return manifest


# ── unpack ────────────────────────────────────────────────────────────────────
def _decrypt_and_parse(path, password):
    raw = _read(path)
    if raw[:6] != MAGIC:
        raise SecbakError("not a valid .secbak file (magic mismatch)")
    salt, nonce, ct = raw[8:24], raw[24:HEADER_LEN], raw[HEADER_LEN:]
    key = _scrypt_key(password, salt)
    plaintext = AESGCM(key).decrypt(nonce, ct, raw[:HEADER_LEN])
    manifest, blobs = None, {}
    with tarfile.open(fileobj=io.BytesIO(plaintext), mode="r") as tar:
        for m in tar.getmembers():
            data = tar.extractfile(m).read()
            if m.name == "manifest.json":
                manifest = json.loads(data)
            elif NAME_RE.match(m.name) and os.path.basename(m.name) == m.name:
                blobs[m.name] = data
            else:
                raise IntegrityError(f"unexpected file name in the backup: {m.name!r}")
    return manifest, blobs


def _verify_manifest(manifest, blobs):
    by_file = {e["file"]: e["sha256"] for e in manifest["keychains"]}
    for name, data in blobs.items():
        expect = by_file.get(name)
        if expect is None:
            raise IntegrityError(f"{name} is missing from the manifest")
        if _sha256(data) != expect:
            raise IntegrityError(f"{name} sha256 mismatch: corrupt or tampered with")


def unpack(path, password):
    manifest, blobs = _decrypt_and_parse(path, password)
    _verify_manifest(manifest, blobs)
    return manifest, blobs


def _unpack_with_bad_manifest(path, password):
    """Test hook: a database that does not match the manifest after decryption."""
    manifest, blobs = _decrypt_and_parse(path, password)
    first = next(iter(blobs))
    blobs[first] = blobs[first] + b"\x00"  # corrupt it
    _verify_manifest(manifest, blobs)
    return manifest, blobs


# ── restore ───────────────────────────────────────────────────────────────────
def restore(path, dest_dir, password, force=False):
    manifest, blobs = unpack(path, password)
    os.makedirs(dest_dir, exist_ok=True)
    targets = [os.path.join(dest_dir, name) for name in blobs]
    existing = [t for t in targets if os.path.exists(t)]
    if existing and not force:
        raise TargetExistsError(
            f"{len(existing)} target file(s) already exist in {dest_dir}; "
            "use force=True (CLI: --force) to move them aside and overwrite")
    if existing:
        ts = datetime.datetime.now().strftime("%Y%m%dT%H%M%S")
        pre = os.path.join(dest_dir, f".pre-restore-{ts}")
        os.makedirs(pre, exist_ok=True)
        os.chmod(pre, 0o700)
        for t in existing:
            os.replace(t, os.path.join(pre, os.path.basename(t)))  # moved aside, never lost
    for name, data in blobs.items():
        dest = os.path.join(dest_dir, name)
        _write_private(dest, data)
    return manifest


# ── CLI (called by `secrets backup` / `secrets restore`) ─────────────────────
def _password(from_stdin):
    """The backup password. `secrets` hands it over on stdin and never puts it
    in the environment of child processes (security review, fix 7); the
    variable is read only when this module is run by hand."""
    if from_stdin:
        pw = sys.stdin.buffer.read().rstrip(b"\n")
    else:
        pw = os.environ.get("SECRETS_BACKUP_PASSWORD", "").encode()
    if not pw:
        raise SystemExit("error: no backup password given")
    return pw


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(prog="secbak", description=".secbak backup/restore")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("pack", help="make a .secbak")
    p.add_argument("--out", required=True)
    p.add_argument("--openssl-compat", action="store_true")
    p.add_argument("--password-stdin", action="store_true")
    p.add_argument("files", nargs="+")

    r = sub.add_parser("restore", help="restore a .secbak")
    r.add_argument("--dest", required=True)
    r.add_argument("--force", action="store_true")
    r.add_argument("--password-stdin", action="store_true")
    r.add_argument("file")

    args = ap.parse_args(argv)
    pw = _password(args.password_stdin)
    try:
        if args.cmd == "pack":
            m = pack(args.files, args.out, pw, openssl_compat=args.openssl_compat)
            n = len(m["keychains"])
            print(f"✓ {n} keychain(s) → {args.out}")
        elif args.cmd == "restore":
            m = restore(args.file, args.dest, pw, force=args.force)
            print(f"✓ {len(m['keychains'])} keychain(s) restored → {args.dest}")
    except TargetExistsError as e:
        raise SystemExit(f"error: {e}")
    except IntegrityError as e:
        raise SystemExit(f"error: integrity check failed: {e}")
    return 0


if __name__ == "__main__":
    main()
