import CryptoKit
import Foundation
import Security
import Testing

@testable import MoteCore

@Suite("CRX")
struct CRXTests {
    @Test(
        "Finds an extension id in links and bare text",
        arguments: [
            ("https://chromewebstore.google.com/detail/ublock/cjpalhdlnbpafiamejdnhcphjbkeiagm", "cjpalhdlnbpafiamejdnhcphjbkeiagm"),
            ("https://chrome.google.com/webstore/detail/CJPALHDLNBPAFIAMEJDNHCPHJBKEIAGM?hl=en", "cjpalhdlnbpafiamejdnhcphjbkeiagm"),
            ("cjpalhdlnbpafiamejdnhcphjbkeiagm", "cjpalhdlnbpafiamejdnhcphjbkeiagm"),
        ])
    func findsID(text: String, expected: String) {
        #expect(CRX.extensionID(in: text) == expected)
    }

    @Test(
        "Ignores text that isn't exactly an id",
        arguments: [
            "", "not an id",
            "cjpalhdlnbpafiamejdnhcphjbkeiag",  // 31 letters
            "cjpalhdlnbpafiamejdnhcphjbkeiagmx",  // 33 letters
            "zjpalhdlnbpafiamejdnhcphjbkeiagm",  // z is outside a–p
        ])
    func ignoresNonIDs(text: String) {
        #expect(CRX.extensionID(in: text) == nil)
    }

    @Test("The download URL asks the store for a CRX3")
    func downloadURL() throws {
        let url = CRX.downloadURL(for: "cjpalhdlnbpafiamejdnhcphjbkeiagm")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "clients2.google.com")
        #expect(components.queryItems?.first { $0.name == "acceptformat" }?.value == "crx3")
        #expect(components.queryItems?.first { $0.name == "x" }?.value == "id=cjpalhdlnbpafiamejdnhcphjbkeiagm&installsource=ondemand&uc")
    }

    @Test("A correctly signed package yields its archive")
    func acceptsSignedPackage() throws {
        let package = try SignedCRX(archive: Data("zip bytes".utf8))
        #expect(try CRX.verifiedArchive(package.data, extensionID: package.id) == Data("zip bytes".utf8))
    }

    @Test("A package whose archive was changed is refused")
    func refusesTamperedArchive() throws {
        let package = try SignedCRX(archive: Data("zip bytes".utf8))
        var tampered = package.data
        tampered[tampered.count - 1] ^= 0xff
        #expect(throws: CRX.Failure.invalidSignature) {
            try CRX.verifiedArchive(tampered, extensionID: package.id)
        }
    }

    @Test("A package passed off under another id is refused")
    func refusesWrongID() throws {
        let package = try SignedCRX(archive: Data("zip bytes".utf8))
        #expect(throws: CRX.Failure.invalidSignature) {
            try CRX.verifiedArchive(package.data, extensionID: String(repeating: "a", count: 32))
        }
    }

    @Test(
        "Data that isn't a CRX3 is refused",
        arguments: [
            Data(), Data("PK\u{3}\u{4}not a crx".utf8), Data("Cr24".utf8) + Data([2, 0, 0, 0, 0, 0, 0, 0, 0]),
        ])
    func refusesNonCRX(data: Data) {
        #expect(throws: CRX.Failure.notCRX) {
            try CRX.verifiedArchive(data, extensionID: String(repeating: "a", count: 32))
        }
    }

    @Test("Unpacking replaces the folder with the extension's files")
    func unpacks() throws {
        let workspace = try TemporaryDirectory()
        let source = workspace.url.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(#"{"manifest_version": 3}"#.utf8).write(to: source.appendingPathComponent("manifest.json"))
        let destination = workspace.url.appendingPathComponent("installed")

        try CRX.unpack(try zip(source, in: workspace), into: destination)

        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("manifest.json").path))
    }

    @Test("A package containing a symbolic link is refused")
    func refusesSymbolicLinks() throws {
        let workspace = try TemporaryDirectory()
        let source = workspace.url.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: source.appendingPathComponent("manifest.json"))
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("escape"), withDestinationURL: URL(fileURLWithPath: "/etc")
        )

        #expect(throws: CRX.Failure.unpack) {
            try CRX.unpack(try zip(source, in: workspace), into: workspace.url.appendingPathComponent("installed"))
        }
    }

    private func zip(_ folder: URL, in workspace: TemporaryDirectory) throws -> Data {
        let archive = workspace.url.appendingPathComponent("extension.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--sequesterRsrc", folder.path, archive.path]
        try ditto.run()
        ditto.waitUntilExit()
        return try Data(contentsOf: archive)
    }
}

/// A CRX3 package signed with a fresh RSA key, built the way Chrome does.
private struct SignedCRX {
    let id: String
    let data: Data

    init(archive: Data) throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
            let publicKey = SecKeyCopyPublicKey(privateKey),
            let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?
        else { throw error!.takeRetainedValue() }

        let spki = Self.subjectPublicKeyInfo(rsaPublicKey: pkcs1)
        let idBytes = Array(SHA256.hash(data: spki).prefix(16))
        id = CRX.extensionID(fromHashPrefix: idBytes)

        let signedHeader = Self.field(1, idBytes)
        var message = Data("CRX3 SignedData".utf8)
        message.append(0)
        message.append(contentsOf: Self.littleEndian32(signedHeader.count))
        message.append(contentsOf: signedHeader)
        message.append(archive)
        guard
            let signature = SecKeyCreateSignature(
                privateKey, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, &error
            ) as Data?
        else { throw error!.takeRetainedValue() }

        let proof = Self.field(1, [UInt8](spki)) + Self.field(2, [UInt8](signature))
        let header = Self.field(2, proof) + Self.field(10000, signedHeader)

        var crx = Data("Cr24".utf8)
        crx.append(contentsOf: Self.littleEndian32(3))
        crx.append(contentsOf: Self.littleEndian32(header.count))
        crx.append(contentsOf: header)
        crx.append(archive)
        data = crx
    }

    private static func littleEndian32(_ value: Int) -> [UInt8] {
        withUnsafeBytes(of: UInt32(value).littleEndian, Array.init)
    }

    private static func varint(_ value: Int) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value > 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value > 0
        return bytes
    }

    private static func field(_ number: Int, _ bytes: [UInt8]) -> [UInt8] {
        varint(number << 3 | 2) + varint(bytes.count) + bytes
    }

    /// Wraps a PKCS#1 RSA key in the SubjectPublicKeyInfo DER that CRX headers carry.
    private static func subjectPublicKeyInfo(rsaPublicKey: Data) -> Data {
        func length(_ count: Int) -> [UInt8] {
            if count < 0x80 { return [UInt8(count)] }
            let bytes = withUnsafeBytes(of: UInt32(count).bigEndian, Array.init).drop { $0 == 0 }
            return [0x80 | UInt8(bytes.count)] + bytes
        }
        func element(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] { [tag] + length(content.count) + content }

        let rsaEncryption: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00]
        let algorithm = element(0x30, rsaEncryption)
        let key = element(0x03, [0x00] + [UInt8](rsaPublicKey))
        return Data(element(0x30, algorithm + key))
    }
}

/// A folder that is removed when the test finishes.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("MoteCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}
