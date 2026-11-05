// Evaluate the public device chain with the same Apple trust policy used by
// Dart SecureSocket on iOS/macOS. No private key or pairing token is needed.
import Foundation
import Security

func certificate(_ path: String) throws -> SecCertificate {
    let pem = try String(contentsOfFile: path, encoding: .utf8)
    let body = pem.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
        .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
    guard let der = Data(base64Encoded: body, options: .ignoreUnknownCharacters),
          let cert = SecCertificateCreateWithData(nil, der as CFData) else {
        throw NSError(domain: "AquaHatch.Certificate", code: 1)
    }
    return cert
}

let ca = try certificate(CommandLine.arguments[1])
let server = try certificate(CommandLine.arguments[2])
let hostname = CommandLine.arguments[3]
var trust: SecTrust?
let status = SecTrustCreateWithCertificates([server] as CFArray,
    SecPolicyCreateSSL(true, hostname as CFString), &trust)
guard status == errSecSuccess, let trust = trust else { exit(2) }
SecTrustSetAnchorCertificates(trust, [ca] as CFArray)
SecTrustSetAnchorCertificatesOnly(trust, true)
SecTrustSetNetworkFetchAllowed(trust, false)
var error: CFError?
let verified = SecTrustEvaluateWithError(trust, &error)
print("APPLE_DEVICE_CERTIFICATE_VERIFIED=\(verified)")
if let error = error {
    print("APPLE_TRUST_ERROR=\(error)")
}
if let result = SecTrustCopyResult(trust) { print("APPLE_TRUST_RESULT=\(result)") }
if let properties = SecTrustCopyProperties(trust) { print("APPLE_TRUST_PROPERTIES=\(properties)") }
exit(verified ? 0 : 1)
