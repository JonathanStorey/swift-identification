import Foundation
import Testing
@testable import Identification

/// Expected values were computed with Python 3.13: `hashlib.sha256(b).digest()[:16]`, with `b`
/// built by the Python expression in each test.
@Suite("Checksum")
struct ChecksumTests {
    @Test("Strings match s.encode()", arguments: [
        ("", "e3b0c44298fc1c149afbf4c8996fb924"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223"),
        ("hello world", "b94d27b9934d3e08a52e52d7da7dabfa"),
        ("caf\u{E9}", "850f7dc43910ff890f8879c0ed26fe69"),
        ("cafe\u{301}", "81ef060bcd98adc7824eb5c1ada83c32"),
        ("🙂", "d06f1525f791397809f9bc98682b5c13"),
    ])
    func strings(_ string: String, _ hex: String) {
        let checksum = string.checksum()
        #expect(checksum.hex == hex)
        #expect(checksum.bytes.count == 16)
        #expect(checksum.description == hex)
        #expect(string.dropFirst(0).checksum() == checksum)
    }

    @Test("Bytes match the bytes as given")
    func bytes() {
        // bytes(range(256))
        let bytes = (0...255).map(UInt8.init)
        #expect(bytes.checksum().hex == "40aff2e9d2d8922e47afd4648e696749")
        #expect(Data(bytes).checksum() == bytes.checksum())
    }

    @Test("Integers match n.to_bytes(width, 'big')")
    func integers() {
        // (5).to_bytes(8, "big", signed=True)
        #expect(Int(5).checksum().hex == "5dee4dd60ff8d0ba9900fe91e90e0dcf")
        #expect(Int64(5).checksum() == Int(5).checksum())
        // (-1).to_bytes(8, "big", signed=True)
        #expect(Int(-1).checksum().hex == "12a3ae445661ce5dee78d0650d33362d")
        // (5).to_bytes(4, "big", signed=True)
        #expect(Int32(5).checksum().hex == "221f8af2372a95064f2ef7d7712216a9")
        // bytes([255])
        #expect(UInt8(255).checksum().hex == "a8100ae6aa1940d0b663bb31cd466142")
        // (0x1234).to_bytes(2, "big")
        #expect(UInt16(0x1234).checksum().hex == "3a103a4e5729ad68c02a678ae39accfb")
        #expect(UInt(5).checksum() == UInt64(5).checksum())
    }

    @Test("Floating point matches struct.pack('>d') and ('>f')")
    func floatingPoint() {
        #expect(1.5.checksum().hex == "430d595dc1ef65e95d4ebdc1c16a5b1d")
        #expect((-0.0).checksum().hex == "b1b0bee5378188f5250138bcce25855f")
        #expect(Float(1.5).checksum().hex == "314ed632b7fb5d384c2dde92e5f3acc0")
    }

    @Test("Bools match bytes([b]) and UUIDs match u.bytes")
    func boolsAndUUIDs() {
        #expect(true.checksum().hex == "4bf5122f344554c53bde2ebb8cd2b7e3")
        #expect(false.checksum().hex == "6e340b9cffb37a989ca544e6bb780a2c")
        // uuid.NAMESPACE_DNS.bytes
        #expect(UUID.dns.checksum().hex == "4ebc3bf944587d83baaef9d9dc2ad979")
    }

    @Test("Keeps every bit in its UUID, like uuid.UUID(bytes=...)")
    func uuid() {
        #expect("abc".checksum().uuid.uuidString == "BA7816BF-8F01-CFEA-4141-40DE5DAE2223")
        #expect("hello world".checksum().uuid.uuidString == "B94D27B9-934D-3E08-A52E-52D7DA7DABFA")
    }

    @Test("Strings hash as given unless the digester asks for NFC")
    func normalization() {
        let composed = "caf\u{E9}"
        let decomposed = "cafe\u{301}"
        // Swift calls these equal, but their UTF-8 bytes differ.
        #expect(composed == decomposed)
        #expect(composed.checksum() != decomposed.checksum())
        #expect(decomposed.checksum(using: Digester(normalization: .nfc)) == composed.checksum())
    }
}

@Suite("Digester")
struct DigesterTests {
    struct Record: Digestible {
        var name: String
        var count: Int
        var namespace: UUID

        func digest(into digester: inout Digester) {
            digester.combine(name)
            digester.combine(count)
            digester.combine(namespace)
        }
    }

    @Test("Combining matches successive h.update() calls")
    func combine() {
        // h.update("id".encode()); h.update((42).to_bytes(8, "big", signed=True));
        // h.update(uuid.NAMESPACE_URL.bytes)
        let expected = "dba712204f06f34b6fcbe0a265be9113"
        #expect(Record(name: "id", count: 42, namespace: .url).checksum().hex == expected)

        var digester = Digester()
        digester.combine("id")
        digester.combine(42)
        digester.combine(bytes: withUnsafeBytes(of: UUID.url.uuid) { Array($0) })
        #expect(digester.finalize().hex == expected)
    }

    @Test("Appends without separators")
    func concatenation() {
        #expect(["a", "bc"].checksum() == "abc".checksum())
        #expect(["ab", "c"].checksum() == ["a", "bc"].checksum())
    }

    @Test("Continues from what the digester already holds")
    func using() {
        var prefix = Digester()
        prefix.combine("ab")
        #expect("c".checksum(using: prefix) == "abc".checksum())
    }
}
