import CryptoKit
import Darwin
import Foundation

struct SigningError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

func publicKey(_ url: URL) throws -> Curve25519.Signing.PublicKey {
    let text = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = Data(base64Encoded: text) else { throw SigningError("Invalid update public key.") }
    return try Curve25519.Signing.PublicKey(rawRepresentation: data)
}

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else { throw SigningError("Expected generate, sign or verify.") }
    switch command {
    case "generate":
        guard args.count == 2 else { throw SigningError("Usage: generate PRIVATE_KEY_PATH") }
        let key = Curve25519.Signing.PrivateKey()
        _ = umask(0o077)
        try key.rawRepresentation.write(to: URL(fileURLWithPath: args[1]), options: .withoutOverwriting)
        print(key.publicKey.rawRepresentation.base64EncodedString())
    case "sign":
        guard args.count == 4 else { throw SigningError("Usage: sign PRIVATE_KEY_PATH PUBLIC_KEY_PATH ARCHIVE") }
        let privateURL = URL(fileURLWithPath: args[1])
        let attributes = try FileManager.default.attributesOfItem(atPath: privateURL.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber, permissions.intValue & 0o077 == 0 else {
            throw SigningError("The private key must have no group or other permissions.")
        }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: privateURL))
        guard try key.publicKey.rawRepresentation == publicKey(URL(fileURLWithPath: args[2])).rawRepresentation else {
            throw SigningError("The private key does not match this application's update public key.")
        }
        let archive = try Data(contentsOf: URL(fileURLWithPath: args[3]), options: .mappedIfSafe)
        print(try key.signature(for: archive).base64EncodedString())
    case "verify":
        guard args.count == 4, let signature = Data(base64Encoded: args[2]) else {
            throw SigningError("Usage: verify PUBLIC_KEY_PATH SIGNATURE ARCHIVE")
        }
        let key = try publicKey(URL(fileURLWithPath: args[1]))
        let archive = try Data(contentsOf: URL(fileURLWithPath: args[3]), options: .mappedIfSafe)
        guard key.isValidSignature(signature, for: archive) else { throw SigningError("Invalid update signature.") }
    default:
        throw SigningError("Expected generate, sign or verify.")
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
