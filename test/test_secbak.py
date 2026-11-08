"""TDD tests voor lib/secbak.py — de .secbak crypto-kern.

Run: python3 -m unittest discover -s test -v   (vanuit repo-root)
Vereist: cryptography (al beschikbaar), openssl CLI (voor compat-test).
"""
import os, sys, json, subprocess, tempfile, unittest, hashlib

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))
import secbak  # noqa: E402

PW = b"correct-horse-battery-staple"


def _write(path, data):
    with open(path, "wb") as fh:
        fh.write(data)


def _read(path):
    with open(path, "rb") as fh:
        return fh.read()


def _fixture_files(d):
    """Maak 3 nep-keychain-db bestanden met willekeurige binaire inhoud."""
    files = {}
    for name in ("dev-config.keychain-db", "system-config.keychain-db", "apple-config.keychain-db"):
        data = os.urandom(2048)
        _write(os.path.join(d, name), data)
        files[name] = data
    return files


class TestRoundTrip(unittest.TestCase):
    def test_pack_then_unpack_is_bit_perfect(self):
        with tempfile.TemporaryDirectory() as d:
            files = _fixture_files(d)
            out = os.path.join(d, "b.secbak")
            secbak.pack([os.path.join(d, n) for n in files], out, PW)
            manifest, blobs = secbak.unpack(out, PW)
            for name, data in files.items():
                self.assertEqual(blobs[name], data, f"{name} niet bit-perfect")

    def test_secbak_has_correct_magic_header(self):
        with tempfile.TemporaryDirectory() as d:
            files = _fixture_files(d)
            out = os.path.join(d, "b.secbak")
            secbak.pack([os.path.join(d, n) for n in files], out, PW)
            raw = _read(out)
            self.assertEqual(raw[:6], b"SECBAK")
            self.assertEqual(raw[6], 1)   # format_version
            self.assertEqual(raw[7], 1)   # kdf_id = scrypt

    def test_file_written_mode_600(self):
        with tempfile.TemporaryDirectory() as d:
            files = _fixture_files(d)
            out = os.path.join(d, "b.secbak")
            secbak.pack([os.path.join(d, n) for n in files], out, PW)
            self.assertEqual(os.stat(out).st_mode & 0o777, 0o600)


class TestAEAD(unittest.TestCase):
    def test_wrong_password_raises(self):
        with tempfile.TemporaryDirectory() as d:
            files = _fixture_files(d)
            out = os.path.join(d, "b.secbak")
            secbak.pack([os.path.join(d, n) for n in files], out, PW)
            with self.assertRaises(Exception):
                secbak.unpack(out, b"wrong-password")

    def test_tampered_ciphertext_raises(self):
        with tempfile.TemporaryDirectory() as d:
            files = _fixture_files(d)
            out = os.path.join(d, "b.secbak")
            secbak.pack([os.path.join(d, n) for n in files], out, PW)
            raw = bytearray(_read(out))
            raw[-1] ^= 0xFF  # flip laatste byte (in de GCM-tag)
            _write(out, raw)
            with self.assertRaises(Exception):
                secbak.unpack(out, PW)


class TestManifest(unittest.TestCase):
    def test_manifest_has_no_password(self):
        with tempfile.TemporaryDirectory() as d:
            files = _fixture_files(d)
            out = os.path.join(d, "b.secbak")
            secbak.pack([os.path.join(d, n) for n in files], out, PW)
            manifest, _ = secbak.unpack(out, PW)
            blob = json.dumps(manifest).lower()
            self.assertNotIn("password", blob)
            self.assertNotIn(PW.decode(), blob)

    def test_manifest_has_sha256_per_db(self):
        with tempfile.TemporaryDirectory() as d:
            files = _fixture_files(d)
            out = os.path.join(d, "b.secbak")
            secbak.pack([os.path.join(d, n) for n in files], out, PW)
            manifest, _ = secbak.unpack(out, PW)
            for entry in manifest["keychains"]:
                self.assertEqual(len(entry["sha256"]), 64)

    def test_unpack_verifies_manifest_checksums(self):
        """unpack() moet aborten als een db niet matcht met manifest-sha256."""
        with tempfile.TemporaryDirectory() as d:
            files = _fixture_files(d)
            out = os.path.join(d, "b.secbak")
            secbak.pack([os.path.join(d, n) for n in files], out, PW)
            # Forceer mismatch via test-hook: pack met een gemanipuleerd manifest
            with self.assertRaises(secbak.IntegrityError):
                secbak._unpack_with_bad_manifest(out, PW)


class TestOpensslCompat(unittest.TestCase):
    def test_openssl_compat_blob_decryptable_by_openssl_cli(self):
        with tempfile.TemporaryDirectory() as d:
            files = _fixture_files(d)
            out = os.path.join(d, "b.secbak.ossl")
            secbak.pack([os.path.join(d, n) for n in files], out, PW, openssl_compat=True)
            # Decrypt met kale openssl + untar → moet de db's teruggeven
            dec = subprocess.run(
                ["openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-iter", "100000",
                 "-md", "sha256", "-in", out, "-pass", "pass:" + PW.decode()],
                capture_output=True)
            self.assertEqual(dec.returncode, 0, dec.stderr.decode())
            # de plaintext is een tar; extract en vergelijk één db
            tdir = os.path.join(d, "x"); os.makedirs(tdir)
            tpath = os.path.join(d, "p.tar"); _write(tpath, dec.stdout)
            subprocess.run(["tar", "-xf", tpath, "-C", tdir], check=True)
            got = _read(os.path.join(tdir, "dev-config.keychain-db"))
            self.assertEqual(got, files["dev-config.keychain-db"])

    def test_openssl_compat_writes_sha256_sidecar(self):
        with tempfile.TemporaryDirectory() as d:
            files = _fixture_files(d)
            out = os.path.join(d, "b.secbak.ossl")
            secbak.pack([os.path.join(d, n) for n in files], out, PW, openssl_compat=True)
            sidecar = out + ".sha256"
            self.assertTrue(os.path.exists(sidecar))
            expect = hashlib.sha256(_read(out)).hexdigest()
            self.assertIn(expect, _read(sidecar).decode())


class TestRestoreSafety(unittest.TestCase):
    def test_restore_moves_existing_files_not_overwrite(self):
        with tempfile.TemporaryDirectory() as d:
            files = _fixture_files(d)
            out = os.path.join(d, "b.secbak")
            secbak.pack([os.path.join(d, n) for n in files], out, PW)
            dest = os.path.join(d, "keychains"); os.makedirs(dest)
            # bestaand bestand met ANDERE inhoud op de doel-locatie
            existing = os.path.join(dest, "dev-config.keychain-db")
            _write(existing, b"OUD-BESTAND-NIET-OVERSCHRIJVEN")
            secbak.restore(out, dest, PW, force=True)
            # restored content moet kloppen
            self.assertEqual(_read(existing), files["dev-config.keychain-db"])
            # het oude bestand moet bewaard zijn in een .pre-restore-* map (niet weg)
            pre = [p for p in os.listdir(dest) if p.startswith(".pre-restore-")]
            self.assertTrue(pre, "bestaand bestand niet weggezet vóór overschrijven")
            moved = os.path.join(dest, pre[0], "dev-config.keychain-db")
            self.assertEqual(_read(moved), b"OUD-BESTAND-NIET-OVERSCHRIJVEN")

    def test_restore_creates_dest_dir_if_missing(self):
        with tempfile.TemporaryDirectory() as d:
            files = _fixture_files(d)
            out = os.path.join(d, "b.secbak")
            secbak.pack([os.path.join(d, n) for n in files], out, PW)
            dest = os.path.join(d, "new", "nested", "dest")  # bestaat nog niet
            secbak.restore(out, dest, PW)
            self.assertEqual(_read(os.path.join(dest, "dev-config.keychain-db")),
                             files["dev-config.keychain-db"])

    def test_restore_without_force_aborts_when_target_exists(self):
        with tempfile.TemporaryDirectory() as d:
            files = _fixture_files(d)
            out = os.path.join(d, "b.secbak")
            secbak.pack([os.path.join(d, n) for n in files], out, PW)
            dest = os.path.join(d, "keychains"); os.makedirs(dest)
            _write(os.path.join(dest, "dev-config.keychain-db"), b"X")
            with self.assertRaises(secbak.TargetExistsError):
                secbak.restore(out, dest, PW, force=False)


if __name__ == "__main__":
    unittest.main()
