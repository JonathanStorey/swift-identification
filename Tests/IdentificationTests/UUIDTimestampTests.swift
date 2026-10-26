import Foundation
import Testing
@testable import Identification

/// A 2025 date with precision below one microsecond.
let sampleDate = Date(timeIntervalSinceReferenceDate: 783_000_000.123_456_789)

/// Counts adjacent pairs that are not in strictly increasing byte order.
func outOfOrderCount(_ ids: [UUID]) -> Int {
    zip(ids, ids.dropFirst()).count { $0.uuidString >= $1.uuidString }
}

@Suite("UUID v7 layout")
struct UUIDTimestampLayoutTests {
    @Test("Writes version 7 and the RFC 9562 variant")
    func versionAndVariant() throws {
        let id = try UUID.timestamp(sampleDate)
        #expect(id.uuid.6 >> 4 == 7)
        #expect(id.uuid.8 >> 6 == 0b10)
    }

    @Test("Writes Unix milliseconds in the first 48 bits")
    func unixMilliseconds() throws {
        // 783,000,000.123… s after 2001 is 1,761,307,200,123 ms after 1970.
        let id = try UUID.timestamp(sampleDate)
        #expect(id.uuidString.prefix(13) == String(1_761_307_200_123, radix: 16, uppercase: true).leftPadded(to: 12).inserting("-", at: 8))
    }

    @Test("Rejects dates before 1970")
    func rejectsPre1970() {
        #expect(throws: UUID.TimestampError.outOfRange) {
            try UUID.timestamp(Date(timeIntervalSince1970: -1))
        }
    }

    @Test("Rejects dates finer than one tick")
    func rejectsFinePrecision() {
        // Dates near 2001 carry more precision than 2⁻²³ s.
        #expect(throws: UUID.TimestampError.notLosslesslyRepresentable) {
            try UUID.timestamp(Date(timeIntervalSinceReferenceDate: 1.000_000_001))
        }
    }
}

@Suite("Round trip")
struct UUIDTimestampRoundTripTests {
    @Test("Returns the exact Date", arguments: [
        sampleDate,
        Date(timeIntervalSinceReferenceDate: 536_870_912),        // 2018-01-05, start of the 2⁻²³ s range
        Date(timeIntervalSinceReferenceDate: 1_073_741_824.5),    // 2035, coarser spacing
        Date(timeIntervalSinceReferenceDate: 0),                  // the reference date itself
        Date(timeIntervalSince1970: 0),
    ])
    func exact(_ date: Date) throws {
        #expect(Date(from: try TimestampGenerator().next(date)) == date)
    }

    @Test("Returns the exact Date for 100,000 random dates from 2018 to 2035")
    func randomDates() throws {
        var failures = 0
        for _ in 0..<100_000 {
            let date = Date(timeIntervalSinceReferenceDate: .random(in: 536_870_912..<1_073_741_824))
            if Date(from: try TimestampGenerator().next(date)) != date {
                failures += 1
            }
        }
        #expect(failures == 0)
    }

    @Test("Returns the exact Date for 10,000 readings of Date.now")
    func now() throws {
        var failures = 0
        for _ in 0..<10_000 {
            let now = Date.now
            if Date(from: try TimestampGenerator().next(now)) != now {
                failures += 1
            }
        }
        #expect(failures == 0)
    }
}

@Suite("Ordering")
struct UUIDTimestampOrderingTests {
    @Test("Identical dates stay in creation order")
    func identicalDates() throws {
        let generator = TimestampGenerator()
        let ids = try (0..<100_000).map { _ in try generator.next(sampleDate) }
        #expect(outOfOrderCount(ids) == 0)
        #expect(Date(from: ids[0]) == sampleDate)
        let last = Date(timeIntervalSinceReferenceDate: sampleDate.timeIntervalSinceReferenceDate + 99_999 * 0x1p-23)
        #expect(Date(from: ids[99_999]) == last)
    }

    @Test("A tie advances by exactly one step of Date's precision", arguments: [
        (sampleDate, 0x1p-23),                                            // 2018 to 2035: 2⁻²³ s
        (Date(timeIntervalSinceReferenceDate: 1_073_741_824.5), 0x1p-22), // after 2035: 2⁻²² s
        (Date(timeIntervalSinceReferenceDate: 0), 0x1p-23),               // before 2018: one tick
    ])
    func tieStep(_ date: Date, _ step: Double) throws {
        let generator = TimestampGenerator()
        let first = try #require(Date(from: generator.next(date)))
        let second = try #require(Date(from: generator.next(date)))
        #expect(first == date)
        #expect(second.timeIntervalSinceReferenceDate == date.timeIntervalSinceReferenceDate + step)
    }

    @Test("A date inside an advanced run is also advanced")
    func insideAdvancedRun() throws {
        let generator = TimestampGenerator()
        let tick = 0x1p-23
        for _ in 0..<3 {
            _ = try generator.next(sampleDate)  // stored at +0, +1 and +2 ticks
        }
        let next = try generator.next(sampleDate.addingTimeInterval(tick))
        #expect(Date(from: next) == sampleDate.addingTimeInterval(3 * tick))
    }

    @Test("IDs created in a tight loop with Date.now stay in creation order")
    func tightLoop() throws {
        let generator = TimestampGenerator()
        let ids = try (0..<100_000).map { _ in try generator.next() }
        #expect(outOfOrderCount(ids) == 0)
    }

    @Test("A clock step backward keeps the true time")
    func clockStepBackward() throws {
        let generator = TimestampGenerator()
        let first = try generator.next(sampleDate.addingTimeInterval(1))
        let second = try generator.next(sampleDate)
        #expect(Date(from: second) == sampleDate)
        #expect(second.uuidString < first.uuidString)
    }

    @Test("Concurrent use produces unique IDs")
    func concurrentUnique() async throws {
        let generator = TimestampGenerator()
        let ids = try await withThrowingTaskGroup(of: [UUID].self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try (0..<10_000).map { _ in try generator.next() }
                }
            }
            return try await group.reduce(into: []) { $0 += $1 }
        }
        #expect(Set(ids).count == 80_000)
    }
}

@Suite("UUID.timestamp property")
struct UUIDTimestampPropertyTests {
    @Test("Encodes the current moment")
    func currentMoment() throws {
        let before = Date.now
        let id = UUID.timestamp
        let after = Date.now
        let date = try #require(Date(from: id))
        // A tie can advance the date by a few 119 ns steps past the clock reading.
        #expect(before <= date && date <= after.addingTimeInterval(0.001))
    }

    @Test("Successive values are distinct")
    func distinct() {
        let ids = (0..<10_000).map { _ in UUID.timestamp }
        #expect(Set(ids).count == ids.count)
    }

    @Test("Coexists with the function", .timeLimit(.minutes(1)))
    func coexists() throws {
        let fromProperty: UUID = UUID.timestamp
        let fromFunction: UUID = try UUID.timestamp()
        #expect(fromProperty != fromFunction)
    }

    @Test("Falls back to a representable date", arguments: [
        Date(timeIntervalSinceReferenceDate: 1.000_000_001),   // finer than one tick
        Date(timeIntervalSince1970: -86_400),                   // before 1970
        Date.distantFuture,
    ])
    func fallback(_ date: Date) throws {
        let representable = UUID.representableDate(near: date)
        #expect(Date(from: try TimestampGenerator().next(representable)) == representable)
    }
}

@Suite("Date(from:)")
struct DateFromUUIDTests {
    @Test("Returns nil for a random version 4 UUID")
    func version4() {
        #expect(Date(from: UUID()) == nil)
    }

    @Test("Returns nil when the tick index points past its millisecond")
    func tickIndexPastMillisecond() throws {
        // Version 7, variant 10, tick index 0x3FFF.
        let id = try #require(UUID(uuidString: "0190A1B2-C3D4-7FFF-B000-000000000000"))
        #expect(Date(from: id) == nil)
    }

    @Test("Decodes another generator's version 7 UUID to the correct millisecond")
    func foreignVersion7() throws {
        // Unix milliseconds 0x0190A1B2C3D4, tick index 0.
        let id = try #require(UUID(uuidString: "0190A1B2-C3D4-7000-8000-000000000000"))
        let date = try #require(Date(from: id))
        #expect(try UUID.timestampField(for: date) >> UUID.tickIndexBits == 0x0190A1B2C3D4)
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }

    func inserting(_ character: Character, at offset: Int) -> String {
        var copy = self
        copy.insert(character, at: index(startIndex, offsetBy: offset))
        return copy
    }
}
