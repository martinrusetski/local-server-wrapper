import Foundation
import CryptoKit
let args = CommandLine.arguments
let publicKeyData = Data(base64Encoded: try String(contentsOfFile: args[1], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
let signature = Data(base64Encoded: args[3])!
let archive = try Data(contentsOf: URL(fileURLWithPath: args[2]), options: .mappedIfSafe)
guard key.isValidSignature(signature, for: archive) else {
    fputs("Update signature does not match the app's public key\n", stderr)
    exit(1)
}
print("Update signature verified against the public key embedded in the app.")
