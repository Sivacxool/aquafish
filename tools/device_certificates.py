"""Local-only device certificate issuance compatible with Apple TLS policy."""
from datetime import datetime, timedelta, timezone
from pathlib import Path
from cryptography import x509
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

SERVER_VALIDITY_DAYS = 730  # Apple's private-CA server limit is 825 days.


def _write_key(path, key):
    path.write_bytes(key.private_bytes(serialization.Encoding.PEM,
        serialization.PrivateFormat.TraditionalOpenSSL,
        serialization.NoEncryption()))


def ensure_certificates(private: Path, ca_filename: str, ca_name: str,
                        hostname: str, *, renew: bool = False):
    """Keep an existing valid identity, or explicitly issue/renew its leaf.

    Retain the CA signing key privately so later leaf renewal does not require
    changing app trust. Legacy installations without that key need a new CA
    and matching app + firmware; no TLS verification bypass is used.
    """
    private.mkdir(parents=True, exist_ok=True)
    ca_path, ca_key_path = private/ca_filename, private/'ca-key.pem'
    server_path, key_path = private/'server.pem', private/'server-key.pem'
    now = datetime.now(timezone.utc)
    if server_path.exists() and not renew:
        cert = x509.load_pem_x509_certificate(server_path.read_bytes())
        if (cert.not_valid_after_utc-cert.not_valid_before_utc).days > 825:
            raise ValueError('Legacy server certificate exceeds Apple validity limit. '
                             'Run with --renew-certificate; rebuild matching app and firmware.')
        if cert.not_valid_after_utc <= now:
            raise ValueError('Server certificate expired. Run with --renew-certificate.')
        return False

    rotating_ca = not (ca_path.exists() and ca_key_path.exists())
    if rotating_ca:
        ca_key = ec.generate_private_key(ec.SECP256R1())
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, ca_name)])
        ca = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
            .public_key(ca_key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now-timedelta(days=1)).not_valid_after(now+timedelta(days=3650))
            .add_extension(x509.BasicConstraints(ca=True, path_length=0), True)
            .add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False,
                key_encipherment=False, data_encipherment=False, key_agreement=False,
                key_cert_sign=True, crl_sign=True, encipher_only=None, decipher_only=None), True)
            .add_extension(x509.SubjectKeyIdentifier.from_public_key(ca_key.public_key()), False)
            .sign(ca_key, hashes.SHA256()))
        _write_key(ca_key_path, ca_key)
        ca_path.write_bytes(ca.public_bytes(serialization.Encoding.PEM))
    else:
        ca = x509.load_pem_x509_certificate(ca_path.read_bytes())
        ca_key = serialization.load_pem_private_key(ca_key_path.read_bytes(), None)
        if ca.public_key().public_numbers() != ca_key.public_key().public_numbers():
            raise ValueError('CA signing key does not match certificate.')
        if ca.not_valid_after_utc <= now+timedelta(days=SERVER_VALIDITY_DAYS):
            raise ValueError('CA expires too soon for renewal; plan an explicit CA rotation.')

    key = (serialization.load_pem_private_key(key_path.read_bytes(), None)
           if key_path.exists() else ec.generate_private_key(ec.SECP256R1()))
    start = now-timedelta(days=1)
    cert = (x509.CertificateBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, hostname)]))
        .issuer_name(ca.subject).public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(start).not_valid_after(start+timedelta(days=SERVER_VALIDITY_DAYS))
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), True)
        .add_extension(x509.SubjectAlternativeName([x509.DNSName(hostname)]), False)
        .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), False)
        .add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False,
            key_encipherment=False, data_encipherment=False, key_agreement=False,
            key_cert_sign=False, crl_sign=False, encipher_only=None, decipher_only=None), True)
        .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(ca.public_key()), False)
        .sign(ca_key, hashes.SHA256()))
    _write_key(key_path, key)
    server_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    return rotating_ca
