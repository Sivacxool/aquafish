import tempfile
import unittest
from pathlib import Path
from datetime import datetime, timedelta, timezone
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID
from device_certificates import ensure_certificates


class DeviceCertificatesTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)

    def issue(self, renew=False):
        return ensure_certificates(self.path, 'ca.pem', 'Test CA',
                                   'camera.test.local', renew=renew)

    def test_apple_lifetime_identity_and_signature(self):
        self.assertTrue(self.issue())
        cert = x509.load_pem_x509_certificate((self.path/'server.pem').read_bytes())
        ca = x509.load_pem_x509_certificate((self.path/'ca.pem').read_bytes())
        cert.verify_directly_issued_by(ca)
        self.assertEqual((cert.not_valid_after_utc-cert.not_valid_before_utc).days, 730)
        self.assertIn('camera.test.local', cert.extensions.get_extension_for_class(
            x509.SubjectAlternativeName).value.get_values_for_type(x509.DNSName))

    def test_idempotent_and_renewal_keeps_trust_anchor(self):
        self.issue()
        ca = (self.path/'ca.pem').read_bytes()
        cert = (self.path/'server.pem').read_bytes()
        self.assertFalse(self.issue())
        self.assertEqual(cert, (self.path/'server.pem').read_bytes())
        self.assertFalse(self.issue(renew=True))
        self.assertEqual(ca, (self.path/'ca.pem').read_bytes())
        self.assertNotEqual(cert, (self.path/'server.pem').read_bytes())

    def test_lost_ca_key_requires_new_anchor_on_explicit_renewal(self):
        self.issue()
        old_ca = (self.path/'ca.pem').read_bytes()
        (self.path/'ca-key.pem').unlink()
        self.assertTrue(self.issue(renew=True))
        self.assertNotEqual(old_ca, (self.path/'ca.pem').read_bytes())
        cert = x509.load_pem_x509_certificate((self.path/'server.pem').read_bytes())
        cert.verify_directly_issued_by(x509.load_pem_x509_certificate(
            (self.path/'ca.pem').read_bytes()))

    def test_legacy_ten_year_certificate_is_not_silently_reused(self):
        key = ec.generate_private_key(ec.SECP256R1())
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'legacy')])
        now = datetime.now(timezone.utc)
        cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
            .public_key(key.public_key()).serial_number(1)
            .not_valid_before(now-timedelta(days=1))
            .not_valid_after(now+timedelta(days=3650)).sign(key, hashes.SHA256()))
        data = cert.public_bytes(serialization.Encoding.PEM)
        (self.path/'server.pem').write_bytes(data)
        with self.assertRaisesRegex(ValueError, '--renew-certificate'):
            self.issue()
        self.assertEqual(data, (self.path/'server.pem').read_bytes())


if __name__ == '__main__':
    unittest.main()
