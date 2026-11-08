"""Tests for the secbak.py CLI (called by `secrets backup` / `secrets restore`).

Contract:
  python3 secbak.py pack    --out FILE [--openssl-compat] [--password-stdin] PATH...
  python3 secbak.py restore --dest DIR [--force] [--password-stdin] FILE
`secrets` passes the password on stdin (--password-stdin); run by hand, the
module also reads SECRETS_BACKUP_PASSWORD.
"""
import os, sys, subprocess, tempfile, unittest

LIB = os.path.join(os.path.dirname(__file__), "..", "lib")
SECBAK = os.path.join(LIB, "secbak.py")
sys.path.insert(0, LIB)
import secbak  # noqa: E402

PW = "cli-test-password"


def _write(path, data):
    with open(path, "wb") as fh:
        fh.write(data)


def _read(path):
    with open(path, "rb") as fh:
        return fh.read()


def _run(args, pw=PW):
    env = dict(os.environ, SECRETS_BACKUP_PASSWORD=pw)
    return subprocess.run([sys.executable, SECBAK, *args], capture_output=True, text=True, env=env)


class TestCli(unittest.TestCase):
    def test_pack_then_restore_via_cli(self):
        with tempfile.TemporaryDirectory() as d:
            db = os.path.join(d, "dev-config.keychain-db")
            _write(db, os.urandom(1024))
            out = os.path.join(d, "b.secbak")
            r = _run(["pack", "--out", out, db])
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertTrue(os.path.exists(out))

            dest = os.path.join(d, "restored"); os.makedirs(dest)
            r2 = _run(["restore", "--dest", dest, out])
            self.assertEqual(r2.returncode, 0, r2.stderr)
            self.assertEqual(_read(os.path.join(dest, "dev-config.keychain-db")), _read(db))

    def test_restore_without_force_fails_on_existing(self):
        with tempfile.TemporaryDirectory() as d:
            db = os.path.join(d, "dev-config.keychain-db")
            _write(db, os.urandom(512))
            out = os.path.join(d, "b.secbak")
            _run(["pack", "--out", out, db])
            dest = os.path.join(d, "restored"); os.makedirs(dest)
            _write(os.path.join(dest, "dev-config.keychain-db"), b"existing")
            r = _run(["restore", "--dest", dest, out])  # geen --force
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("already exist", (r.stderr + r.stdout).lower())

    def test_missing_password_fails_cleanly(self):
        with tempfile.TemporaryDirectory() as d:
            db = os.path.join(d, "dev-config.keychain-db")
            _write(db, b"x")
            out = os.path.join(d, "b.secbak")
            env = dict(os.environ); env.pop("SECRETS_BACKUP_PASSWORD", None)
            r = subprocess.run([sys.executable, SECBAK, "pack", "--out", out, db],
                               capture_output=True, text=True, env=env)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("no backup password", r.stderr)

    def test_password_on_stdin_and_private_files(self):
        with tempfile.TemporaryDirectory() as d:
            db = os.path.join(d, "dev-config.keychain-db")
            _write(db, b"payload")
            out = os.path.join(d, "b.secbak")
            env = dict(os.environ); env.pop("SECRETS_BACKUP_PASSWORD", None)
            r = subprocess.run([sys.executable, SECBAK, "pack", "--out", out, "--password-stdin", db],
                               input=PW, capture_output=True, text=True, env=env)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(os.stat(out).st_mode & 0o777, 0o600)
            dest = os.path.join(d, "r")
            r = subprocess.run([sys.executable, SECBAK, "restore", "--dest", dest, "--password-stdin", out],
                               input=PW, capture_output=True, text=True, env=env)
            self.assertEqual(r.returncode, 0, r.stderr)
            restored = os.path.join(dest, "dev-config.keychain-db")
            self.assertEqual(_read(restored), b"payload")
            self.assertEqual(os.stat(restored).st_mode & 0o777, 0o600)

    def test_a_name_that_points_outside_is_refused(self):
        import io, json, tarfile
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
        with tempfile.TemporaryDirectory() as d:
            buf = io.BytesIO()
            with tarfile.open(fileobj=buf, mode="w") as tar:
                for name, data in (("manifest.json", json.dumps({"keychains": [{"file": "../evil.keychain-db", "sha256": secbak._sha256(b"x")}]}).encode()),
                                   ("../evil.keychain-db", b"x")):
                    ti = tarfile.TarInfo(name); ti.size = len(data); tar.addfile(ti, io.BytesIO(data))
            salt, nonce = os.urandom(16), os.urandom(12)
            header = secbak.MAGIC + bytes([secbak.FORMAT_VERSION, secbak.KDF_SCRYPT]) + salt + nonce
            ct = AESGCM(secbak._scrypt_key(PW.encode(), salt)).encrypt(nonce, buf.getvalue(), header)
            bad = os.path.join(d, "bad.secbak"); _write(bad, header + ct)
            dest = os.path.join(d, "inner", "dest"); os.makedirs(dest)
            r = _run(["restore", "--dest", dest, bad])
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("unexpected file name", r.stderr)
            self.assertFalse(os.path.exists(os.path.join(d, "inner", "evil.keychain-db")))


if __name__ == "__main__":
    unittest.main()
