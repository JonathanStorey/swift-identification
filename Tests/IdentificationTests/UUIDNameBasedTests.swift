import Foundation
import Testing
@testable import Identification

@Suite("SHA")
struct SHATests {
    static let twoBlocks = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"

    func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    @Test("SHA-1 matches the FIPS 180 test vectors", arguments: [
        ("", "da39a3ee5e6b4b0d3255bfef95601890afd80709"),
        ("abc", "a9993e364706816aba3e25717850c26c9cd0d89d"),
        (twoBlocks, "84983e441c3bd26ebaae4aa1f95129e5e54670f1"),
    ])
    func sha1(_ message: String, _ digest: String) {
        #expect(hex(SHA.sha1(Array(message.utf8))) == digest)
    }

    @Test("SHA-256 matches the FIPS 180 test vectors", arguments: [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        (twoBlocks, "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
    ])
    func sha256(_ message: String, _ digest: String) {
        #expect(hex(SHA.sha256(Array(message.utf8))) == digest)
    }

    @Test("Both handle a million-byte message")
    func millionBytes() {
        let message = [UInt8](repeating: UInt8(ascii: "a"), count: 1_000_000)
        #expect(hex(SHA.sha1(message)).hasPrefix("34aa973cd4c4daa4"))
        #expect(hex(SHA.sha256(message)).hasPrefix("cdc76e5c9914fb92"))
    }
}

@Suite("Name-based UUIDs")
struct UUIDNameBasedTests {
    @Test("Version 5 matches RFC 9562 Appendix A.4")
    func version5() {
        let id = UUID(name: "www.example.com", namespace: .dns)
        #expect(id.uuidString == "2ED6657D-E927-568B-95E1-2665A8AEA6A2")
    }

    @Test("SHA-256 version 8 matches RFC 9562 Appendix B.2")
    func version8() {
        let id = UUID(name: "www.example.com", namespace: .dns, hash: .sha256)
        #expect(id.uuidString == "5C146B14-3C52-8AFD-938A-375D0DF1FBF6")
    }

    @Test("Is deterministic and depends on namespace and name")
    func deterministic() {
        #expect(UUID(name: "a", namespace: .url) == UUID(name: "a", namespace: .url))
        #expect(UUID(name: "a", namespace: .url) != UUID(name: "b", namespace: .url))
        #expect(UUID(name: "a", namespace: .url) != UUID(name: "a", namespace: .dns))
    }

    @Test("Bytes and String produce the same UUID")
    func bytesAndString() {
        #expect(UUID(name: Data("café".utf8), namespace: .oid) == UUID(name: "café", namespace: .oid))
    }

    @Test("Writes the version and variant", arguments: [UUID.NameHash.sha1, .sha256])
    func versionAndVariant(_ hash: UUID.NameHash) {
        let id = UUID(name: "x", namespace: .x500, hash: hash)
        #expect(id.uuid.6 >> 4 == (hash == .sha1 ? 5 : 8))
        #expect(id.uuid.8 >> 6 == 0b10)
    }
}
