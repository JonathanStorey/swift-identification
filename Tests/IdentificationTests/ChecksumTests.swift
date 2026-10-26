import Foundation
import Testing
@testable import Identification

/// Expected values were computed with Python 3.13:
/// `hashlib.sha256(s.encode()).digest()[:16]` and `uuid.UUID(bytes=...)`.
@Suite("Checksum")
struct ChecksumTests {
    @Test("Matches Python's truncated SHA-256", arguments: [
        ("", "e3b0c44298fc1c149afbf4c8996fb924"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223"),
        ("hello world", "b94d27b9934d3e08a52e52d7da7dabfa"),
        ("caf\u{E9}", "850f7dc43910ff890f8879c0ed26fe69"),
        ("cafe\u{301}", "81ef060bcd98adc7824eb5c1ada83c32"),
        ("🙂", "d06f1525f791397809f9bc98682b5c13"),
    ])
    func python(_ string: String, _ hex: String) {
        let checksum = Checksum(string)
        #expect(checksum.hex == hex)
        #expect(checksum.bytes.count == 16)
        #expect(checksum.description == hex)
    }

    @Test("Hashes arbitrary bytes")
    func bytes() {
        // hashlib.sha256(bytes(range(256))).digest()[:16]
        let checksum = Checksum((0...255).map(UInt8.init))
        #expect(checksum.hex == "40aff2e9d2d8922e47afd4648e696749")
        #expect(Checksum(Data("abc".utf8)) == Checksum("abc"))
    }

    @Test("Keeps every bit in its UUID, like uuid.UUID(bytes=...)")
    func uuid() {
        #expect(Checksum("abc").uuid.uuidString == "BA7816BF-8F01-CFEA-4141-40DE5DAE2223")
        #expect(Checksum("hello world").uuid.uuidString == "B94D27B9-934D-3E08-A52E-52D7DA7DABFA")
    }

    @Test("Hashes the bytes as given unless NFC is requested")
    func normalization() {
        let composed = "caf\u{E9}"
        let decomposed = "cafe\u{301}"
        // Swift calls these equal, but their UTF-8 bytes differ.
        #expect(composed == decomposed)
        #expect(Checksum(composed) != Checksum(decomposed))
        #expect(Checksum(decomposed, normalization: .nfc) == Checksum(composed))
        #expect(Checksum(decomposed, normalization: .nfc).hex == "850f7dc43910ff890f8879c0ed26fe69")
    }
}
