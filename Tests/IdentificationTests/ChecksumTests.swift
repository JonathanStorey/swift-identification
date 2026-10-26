import Foundation
import Testing
@testable import Identification

/// Expected values were computed with Python 3.13 and cbor2 6.1:
/// `hashlib.sha256(b).digest()[:16]`, where `b` is
/// `cbor2.dumps(v, canonical=True, datetime_as_timestamp=True)` for the typed encoding and
/// the Python expression in each test for the bytes encoding.
@Suite("Checksum, typed")
struct TypedChecksumTests {
    @Test("Strings match CBOR text strings", arguments: [
        ("", "8d33f520a3c4cef80d2453aef81b612b"),
        ("abc", "a6d89baf01ac02637da09835b28485b2"),
        ("hello world", "a6dc1f38a111301a02f8c66046712cd9"),
        ("caf\u{E9}", "d969116be8b6651a9a0cc2fd6587420c"),
        ("cafe\u{301}", "d2857d41ec1392f3f34dba1073d93c59"),
        ("🙂", "0e541cb755e28c1463e18800e8bff701"),
    ])
    func strings(_ string: String, _ hex: String) {
        let checksum = string.checksum()
        #expect(checksum.hex == hex)
        #expect(checksum.bytes.count == 16)
        #expect(checksum.description == hex)
        #expect(string.dropFirst(0).checksum() == checksum)
    }

    @Test("Bytes match CBOR byte strings")
    func bytes() {
        // bytes(range(256))
        let bytes = (0...255).map(UInt8.init)
        #expect(bytes.checksum().hex == "4c80e10599d518d15f8b1efbda60c328")
        #expect(Data(bytes).checksum() == bytes.checksum())
    }

    @Test("Integers match by value, whatever their width")
    func integers() {
        #expect(Int(5).checksum().hex == "e77b9a9ae9e30b0dbdb6f510a264ef9d")
        #expect(Int32(5).checksum() == Int(5).checksum())
        #expect(UInt8(5).checksum() == Int(5).checksum())
        #expect(Int(-1).checksum().hex == "36a9e7f1c95b82ffb99743e0c5c4ce95")
        #expect(Int16(-500).checksum().hex == "0916d3cb2a903cddb78a97241304bc94")
        #expect(Int(1_000_000).checksum().hex == "cbbec14103147af122feaff2419ad885")
        #expect(UInt64.max.checksum().hex == "2d7cb0927d162df726656d7155780f04")
        #expect(Int64.min.checksum().hex == "67e32b647dedafb41220d36a02052aef")
    }

    @Test("Floating point matches the shortest exact CBOR float")
    func floatingPoint() {
        #expect(1.5.checksum().hex == "b68bb45ecab0329ab815daf44f5a02d2")
        #expect(Float(1.5).checksum() == 1.5.checksum())
        #expect(0.1.checksum().hex == "8a4d00337ef54566f0092ea89930adf2")
        // Float(0.1) is a different value from 0.1, so it differs from 0.1 as Python does.
        #expect(Float(0.1).checksum().hex == "c957587042e74d83a024620582001bce")
        #expect((-0.0).checksum().hex == "e95873bb6549017f8cd72cc8af178667")
        #expect((-0.0).checksum() != 0.0.checksum())
        #expect(Double.nan.checksum().hex == "510364a22f07e10b06ba37c25de66e4b")
        #expect(Float.nan.checksum() == Double.nan.checksum())
        #expect(Double.infinity.checksum().hex == "33198540d806815f249ae78851dafcb8")
        #expect(100_000.0.checksum().hex == "05a7624cd6aa2fc46465dd99039855f1")
    }

    @Test("Half precision bits match IEEE 754", arguments: [
        (0, 0x0000),
        (-0.0, 0x8000),
        (1.5, 0x3E00),
        (65504, 0x7BFF),
        (65520, nil),
        (.infinity, 0x7C00),
        (0x1p-14, 0x0400),
        (0x1p-24, 0x0001),
        (0x3p-24, 0x0003),
        (0x1p-25, nil),
        (0.1, nil),
    ] as [(Float, UInt16?)])
    func halfBits(_ value: Float, _ bits: UInt16?) {
        #expect(Digester.halfBits(value) == bits)
    }

    @Test("Bools, UUIDs and arrays match CBOR")
    func otherTypes() {
        #expect(true.checksum().hex == "27abdeddfe8503496adeb623466caa47")
        #expect(false.checksum().hex == "2017ff3461395672aa0aa4f64894fd2f")
        // uuid.NAMESPACE_DNS
        #expect(UUID.dns.checksum().hex == "7cf1562dc0b172686a82e17b10744bd7")
        #expect(["a", "bc"].checksum().hex == "a40e65039b87e11a65b6d52f1bd334d4")
        #expect(["ab", "c"].checksum().hex == "c56a8852ab50a8f640bacda6b9865739")
        #expect([1, 2].checksum() != [UInt8(1), 2].checksum())
    }

    @Test("Dates match CBOR tag 1 epoch times", arguments: [
        // 2026-10-26T15:00:00Z
        (1_793_026_800.0, "c7a4ad3e243c5d1a7fca161803f74bbb"),
        // 2026-10-26T15:00:00.25Z
        (1_793_026_800.25, "c9350d30e520c8f74781b21770aba818"),
        // 1969-12-31T23:59:59.5Z
        (-0.5, "3640d5b2c6a06a0e79bb74650307d64f"),
    ])
    func dates(_ interval: TimeInterval, _ hex: String) {
        #expect(Date(timeIntervalSince1970: interval).checksum().hex == hex)
    }

    @Test("Dates round to the nearest microsecond")
    func datePrecision() {
        let date = Date(timeIntervalSince1970: 1_793_026_800.25)
        #expect(date.addingTimeInterval(0.000_000_2).checksum() == date.checksum())
        #expect(date.addingTimeInterval(0.000_001).checksum() != date.checksum())
    }

    @Test("Keeps every bit in its UUID, like uuid.UUID(bytes=...)")
    func uuid() {
        #expect("abc".checksum().uuid.uuidString == "A6D89BAF-01AC-0263-7DA0-9835B28485B2")
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

@Suite("Checksum, bytes")
struct BytesChecksumTests {
    let digester = Digester(encoding: .bytes)

    @Test("Strings match s.encode()", arguments: [
        ("", "e3b0c44298fc1c149afbf4c8996fb924"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223"),
        ("hello world", "b94d27b9934d3e08a52e52d7da7dabfa"),
        ("caf\u{E9}", "850f7dc43910ff890f8879c0ed26fe69"),
        ("cafe\u{301}", "81ef060bcd98adc7824eb5c1ada83c32"),
        ("🙂", "d06f1525f791397809f9bc98682b5c13"),
    ])
    func strings(_ string: String, _ hex: String) {
        #expect(string.checksum(using: digester).hex == hex)
    }

    @Test("Bytes match the bytes as given")
    func bytes() {
        // bytes(range(256))
        let bytes = (0...255).map(UInt8.init)
        #expect(bytes.checksum(using: digester).hex == "40aff2e9d2d8922e47afd4648e696749")
        #expect(Data(bytes).checksum(using: digester) == bytes.checksum(using: digester))
    }

    @Test("Integers match n.to_bytes(width, 'big')")
    func integers() {
        // (5).to_bytes(8, "big", signed=True)
        #expect(Int(5).checksum(using: digester).hex == "5dee4dd60ff8d0ba9900fe91e90e0dcf")
        #expect(Int64(5).checksum(using: digester) == Int(5).checksum(using: digester))
        // (-1).to_bytes(8, "big", signed=True)
        #expect(Int(-1).checksum(using: digester).hex == "12a3ae445661ce5dee78d0650d33362d")
        // (5).to_bytes(4, "big", signed=True)
        #expect(Int32(5).checksum(using: digester).hex == "221f8af2372a95064f2ef7d7712216a9")
        // bytes([255])
        #expect(UInt8(255).checksum(using: digester).hex == "a8100ae6aa1940d0b663bb31cd466142")
        // (0x1234).to_bytes(2, "big")
        #expect(UInt16(0x1234).checksum(using: digester).hex == "3a103a4e5729ad68c02a678ae39accfb")
        #expect(UInt(5).checksum(using: digester) == UInt64(5).checksum(using: digester))
    }

    @Test("Floating point matches struct.pack('>d') and ('>f')")
    func floatingPoint() {
        #expect(1.5.checksum(using: digester).hex == "430d595dc1ef65e95d4ebdc1c16a5b1d")
        #expect((-0.0).checksum(using: digester).hex == "b1b0bee5378188f5250138bcce25855f")
        #expect(Float(1.5).checksum(using: digester).hex == "314ed632b7fb5d384c2dde92e5f3acc0")
    }

    @Test("Bools match bytes([b]), UUIDs match u.bytes, dates match microseconds")
    func otherTypes() {
        #expect(true.checksum(using: digester).hex == "4bf5122f344554c53bde2ebb8cd2b7e3")
        #expect(false.checksum(using: digester).hex == "6e340b9cffb37a989ca544e6bb780a2c")
        // uuid.NAMESPACE_DNS.bytes
        #expect(UUID.dns.checksum(using: digester).hex == "4ebc3bf944587d83baaef9d9dc2ad979")
        // (1_793_026_800_250_000).to_bytes(8, "big", signed=True)
        let date = Date(timeIntervalSince1970: 1_793_026_800.25)
        #expect(date.checksum(using: digester).hex == "572a4b315cc239fe2abaee0df8c2284e")
        // (-500_000).to_bytes(8, "big", signed=True)
        let early = Date(timeIntervalSince1970: -0.5)
        #expect(early.checksum(using: digester).hex == "d76bfd40889f26f6b490f480cd929aab")
    }

    @Test("Appends without separators")
    func concatenation() {
        #expect(["a", "bc"].checksum(using: digester) == "abc".checksum(using: digester))
        #expect(["ab", "c"].checksum(using: digester) == ["a", "bc"].checksum(using: digester))
    }
}

@Suite("Date digesting strategies")
struct DateDigestingStrategyTests {
    // 2026-10-26T15:00:00.25Z
    let date = Date(timeIntervalSince1970: 1_793_026_800.25)
    // One Double step later: a different Date with the same seconds since 1970.
    var nextDate: Date { Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.nextUp) }

    func checksum(
        _ date: Date, _ strategy: Digester.DateDigestingStrategy, _ encoding: Digester.Encoding = .typed
    ) -> String {
        date.checksum(using: Digester(encoding: encoding, dateDigestingStrategy: strategy)).hex
    }

    @Test("Deferred to Date matches the Double since 2001 and tells every Date apart")
    func deferredToDate() {
        // cbor2.dumps(814719600.25, canonical=True) and struct.pack(">d", 814719600.25)
        #expect(checksum(date, .deferredToDate) == "26de88594df6fce2fc537e68cc3f1d6f")
        #expect(checksum(date, .deferredToDate, .bytes) == "07d64cc6bc1def487066c6903df8a9f7")
        // math.nextafter(814719600.25, math.inf)
        #expect(checksum(nextDate, .deferredToDate) == "f69a844180d93a214e9c2e9ad2e73cb6")
        #expect(checksum(nextDate, .deferredToDate, .bytes) == "648eb99f82937e4dec7ddfd44bf4e391")
    }

    @Test("Seconds since 1970 matches CBOR tag 1 around a float")
    func secondsSince1970() {
        // cbor2.dumps(cbor2.CBORTag(1, 1793026800.25), canonical=True)
        #expect(checksum(date, .secondsSince1970) == "c9350d30e520c8f74781b21770aba818")
        // struct.pack(">d", 1793026800.25)
        #expect(checksum(date, .secondsSince1970, .bytes) == "6cd5b1c5c3cf21923f916906395100f1")
        // A whole second is still a float: cbor2.CBORTag(1, 1793026800.0)
        let whole = Date(timeIntervalSince1970: 1_793_026_800)
        #expect(checksum(whole, .secondsSince1970) == "67e98b31b4b8d41f6eb110014b2117fa")
        // Dates closer than one Double step since 1970 merge.
        #expect(checksum(nextDate, .secondsSince1970) == checksum(date, .secondsSince1970))
    }

    @Test("Milliseconds since 1970 rounds like a datetime with whole milliseconds")
    func millisecondsSince1970() {
        // 2026-10-26T15:00:00.123Z, and (1793026800123).to_bytes(8, "big", signed=True)
        let date = Date(timeIntervalSince1970: 1_793_026_800.123_4)
        #expect(checksum(date, .millisecondsSince1970) == "76cb69258db5b8b92b9da6d065ef8d25")
        #expect(checksum(date, .millisecondsSince1970, .bytes) == "e272a56f38c36873a9b51c38bac9ad85")
    }

    @Test("Microseconds since 1970 is the default")
    func microsecondsSince1970() {
        #expect(checksum(date, .microsecondsSince1970) == date.checksum().hex)
        #expect(checksum(nextDate, .microsecondsSince1970) == checksum(date, .microsecondsSince1970))
    }

    @Test("ISO 8601 matches cbor2's default datetime encoding", arguments: [
        (1_793_026_800.0, "2026-10-26T15:00:00Z", "0d7022a5fa53083ee33a92e1cfd5c3ea"),
        (1_793_026_800.25, "2026-10-26T15:00:00.250000Z", "53063d6b637dec79fd942de547bd9ba8"),
        (-0.5, "1969-12-31T23:59:59.500000Z", "a76c772bbda8e0f9757f523aa6c3b245"),
        (951_782_400.000_001, "2000-02-29T00:00:00.000001Z", "28bf48e702244fc18489e6d8ae317cb9"),
    ])
    func iso8601(_ interval: TimeInterval, _ text: String, _ hex: String) {
        // cbor2.dumps(dt, canonical=True) and dt.isoformat().replace("+00:00", "Z").encode()
        let date = Date(timeIntervalSince1970: interval)
        #expect(checksum(date, .iso8601) == hex)
        #expect(checksum(date, .iso8601, .bytes) == text.checksum(using: Digester(encoding: .bytes)).hex)
    }

    @Test("Custom digests with the closure")
    func custom() {
        let strategy = Digester.DateDigestingStrategy.custom { date, digester in
            digester.combine(date.ISO8601Format())
        }
        #expect(checksum(date, strategy) == "2026-10-26T15:00:00Z".checksum().hex)
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

    @Test("Typed combining matches a CBOR sequence")
    func typedSequence() {
        // b"".join(cbor2.dumps(v, canonical=True) for v in ("id", 42, uuid.NAMESPACE_URL))
        let record = Record(name: "id", count: 42, namespace: .url)
        #expect(record.checksum().hex == "bd05534442af9152d3732e0fc7d92bb3")
    }

    @Test("Bytes combining matches successive h.update() calls")
    func bytesSequence() {
        // h.update("id".encode()); h.update((42).to_bytes(8, "big", signed=True));
        // h.update(uuid.NAMESPACE_URL.bytes)
        let expected = "dba712204f06f34b6fcbe0a265be9113"
        let record = Record(name: "id", count: 42, namespace: .url)
        #expect(record.checksum(using: Digester(encoding: .bytes)).hex == expected)

        var digester = Digester(encoding: .bytes)
        digester.combine("id")
        digester.combine(42)
        digester.combine(bytes: withUnsafeBytes(of: UUID.url.uuid) { Array($0) })
        #expect(digester.finalize().hex == expected)
    }

    @Test("Continues from what the digester already holds")
    func using() {
        var prefix = Digester()
        prefix.combine("ab")
        let both = ["ab", "c"].reduce(into: Digester()) { $0.combine($1) }
        #expect("c".checksum(using: prefix) == both.finalize())
    }
}
