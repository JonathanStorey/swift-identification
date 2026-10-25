import Foundation
import Testing
@testable import Identification

typealias Compatibility = UUID.TimestampCompatibility

/// A 2025 date with precision below one microsecond.
let sampleDate = Date(timeIntervalSinceReferenceDate: 783_000_000.123_456_789)

/// Counts adjacent pairs that are not in strictly increasing byte order.
func outOfOrderCount(_ ids: [UUID]) -> Int {
    zip(ids, ids.dropFirst()).count { $0.uuidString >= $1.uuidString }
}

@Suite("UUID v7 layout")
struct UUIDTimestampLayoutTests {
    @Test("Writes version 7 and the RFC 9562 variant", arguments: Compatibility.allCases)
    func versionAndVariant(_ compatibility: Compatibility) throws {
        let id = try UUID.timestamp(sampleDate, compatibility: compatibility)
        #expect(id.uuid.6 >> 4 == 7)
        #expect(id.uuid.8 >> 6 == 0b10)
    }

    @Test("All options agree on the 48-bit millisecond field", arguments: Compatibility.allCases)
    func sharedMillisecondField(_ compatibility: Compatibility) throws {
        let reference = try UUID.timestamp(sampleDate, compatibility: .milliseconds)
        let id = try UUID.timestamp(sampleDate, compatibility: compatibility)
        #expect(id.uuidString.prefix(13) == reference.uuidString.prefix(13))
    }

    @Test("Rejects dates before 1970", arguments: Compatibility.allCases)
    func rejectsPre1970(_ compatibility: Compatibility) {
        #expect(throws: UUID.TimestampError.outOfRange) {
            try UUID.timestamp(Date(timeIntervalSince1970: -1), compatibility: compatibility)
        }
    }

    @Test("Lossless rejects dates finer than its tick")
    func losslessRejectsFinePrecision() {
        // Dates near 2001 carry more precision than 2⁻²³ s.
        #expect(throws: UUID.TimestampError.notLosslesslyRepresentable) {
            try UUID.timestamp(Date(timeIntervalSinceReferenceDate: 1.000_000_001), compatibility: .lossless)
        }
    }
}

@Suite("Round trip")
struct UUIDTimestampRoundTripTests {
    @Test("Milliseconds truncates to the millisecond")
    func millisecondsTruncates() throws {
        let decoded = try #require(UUID.timestamp(sampleDate, compatibility: .milliseconds).date(compatibility: .milliseconds))
        #expect(decoded != sampleDate)
        #expect(sampleDate.timeIntervalSince(decoded) >= 0)
        #expect(sampleDate.timeIntervalSince(decoded) < 0.001)
    }

    @Test("Sub-millisecond truncates to 1/4096 ms")
    func subMillisecondTruncates() throws {
        let decoded = try #require(UUID.timestamp(sampleDate, compatibility: .subMillisecond).date(compatibility: .subMillisecond))
        #expect(sampleDate.timeIntervalSince(decoded) >= 0)
        #expect(sampleDate.timeIntervalSince(decoded) < 0.001 / 4096 + 1e-9)
    }

    @Test("Sub-millisecond loses a date two Date ticks past a millisecond boundary")
    func subMillisecondLosesPrecision() throws {
        // 2 × 2⁻²³ s ≈ 238 ns is below one 1/4096 ms step (≈ 244 ns), so it truncates to the boundary.
        let boundary = Date(timeIntervalSinceReferenceDate: 783_000_000)
        let date = Date(timeIntervalSinceReferenceDate: 783_000_000 + 2 * 0x1p-23)
        let decoded = try UUID.timestamp(date, compatibility: .subMillisecond).date(compatibility: .subMillisecond)
        #expect(decoded == boundary)
    }

    @Test("Lossless returns the exact Date", arguments: [
        sampleDate,
        Date(timeIntervalSinceReferenceDate: 536_870_912),        // 2018-01-05, start of the 2⁻²³ s range
        Date(timeIntervalSinceReferenceDate: 1_073_741_824.5),    // 2035, coarser spacing
        Date(timeIntervalSinceReferenceDate: 0),                  // the reference date itself
        Date(timeIntervalSince1970: 0),
    ])
    func losslessExact(_ date: Date) throws {
        let decoded = try UUID.timestamp(date, compatibility: .lossless).date(compatibility: .lossless)
        #expect(decoded == date)
    }

    @Test("Lossless returns the exact Date for 100,000 random current dates")
    func losslessRandomDates() throws {
        var failures = 0
        for _ in 0..<100_000 {
            let date = Date(timeIntervalSinceReferenceDate: .random(in: 536_870_912..<1_073_741_824))
            if try UUID.timestamp(date, compatibility: .lossless).date(compatibility: .lossless) != date {
                failures += 1
            }
        }
        #expect(failures == 0)
    }

    @Test("Round trip of Date.now", arguments: Compatibility.allCases)
    func roundTripNow(_ compatibility: Compatibility) throws {
        var exact = 0
        let count = 10_000
        for _ in 0..<count {
            let now = Date.now
            if try UUID.timestamp(now, compatibility: compatibility).date(compatibility: compatibility) == now {
                exact += 1
            }
        }
        print("[round-trip] \(compatibility.rawValue): \(exact)/\(count) exact")
        if compatibility == .lossless {
            #expect(exact == count)
        }
    }
}

@Suite("Ordering")
struct UUIDTimestampOrderingTests {
    /// Generates IDs for dates that advance by `step` seconds each iteration.
    func ids(step: TimeInterval, compatibility: Compatibility, count: Int = 10_000) throws -> [UUID] {
        try (0..<count).map { index in
            try UUID.timestamp(sampleDate.addingTimeInterval(Double(index) * step), compatibility: compatibility, ordering: .unordered)
        }
    }

    @Test("Dates 1 µs apart stay ordered with sub-millisecond time", arguments: [Compatibility.subMillisecond, .lossless])
    func microsecondSteps(_ compatibility: Compatibility) throws {
        #expect(try outOfOrderCount(ids(step: 1e-6, compatibility: compatibility)) == 0)
    }

    @Test("Dates 1 µs apart lose order with milliseconds only")
    func microsecondStepsMilliseconds() throws {
        #expect(try outOfOrderCount(ids(step: 1e-6, compatibility: .milliseconds)) > 0)
    }

    @Test("Dates one Date tick apart stay ordered only with lossless")
    func tickSteps() throws {
        let tick = 0x1p-23
        #expect(try outOfOrderCount(ids(step: tick, compatibility: .lossless)) == 0)
        #expect(try outOfOrderCount(ids(step: tick, compatibility: .subMillisecond)) > 0)
    }

    @Test("Unordered IDs created in a tight loop with Date.now", arguments: Compatibility.allCases)
    func tightLoop(_ compatibility: Compatibility) throws {
        let count = 100_000
        var ids: [UUID] = []
        var dates: [Date] = []
        ids.reserveCapacity(count)
        dates.reserveCapacity(count)
        for _ in 0..<count {
            let now = Date.now
            dates.append(now)
            ids.append(try UUID.timestamp(now, compatibility: compatibility, ordering: .unordered))
        }
        let repeatedDates = zip(dates, dates.dropFirst()).count { $0 == $1 }
        let outOfOrder = outOfOrderCount(ids)
        print("[tight-loop] \(compatibility.rawValue): \(outOfOrder)/\(count - 1) out of order, \(repeatedDates) repeated Date.now values")
        // Whether this passes depends on how often the clock repeats a value, which varies by
        // platform and load. No option breaks ties, so none is guaranteed to stay ordered.
        withKnownIssue("Ordering is not guaranteed when Date.now repeats", isIntermittent: true) {
            #expect(outOfOrder == 0)
        }
    }

    @Test("Identical dates lose order in every option when unordered", arguments: Compatibility.allCases)
    func identicalDates(_ compatibility: Compatibility) throws {
        let ids = try (0..<1_000).map { _ in try UUID.timestamp(sampleDate, compatibility: compatibility, ordering: .unordered) }
        #expect(outOfOrderCount(ids) > 0)
    }
}

@Suite("Monotonic ordering")
struct UUIDTimestampMonotonicTests {
    @Test("Identical dates stay ordered", arguments: Compatibility.allCases)
    func identicalDates(_ compatibility: Compatibility) throws {
        let generator = UUID.TimestampGenerator()
        let ids = try (0..<100_000).map { _ in try generator.next(sampleDate, compatibility: compatibility) }
        #expect(outOfOrderCount(ids) == 0)
    }

    @Test("IDs created in a tight loop with Date.now stay ordered", arguments: Compatibility.allCases)
    func tightLoop(_ compatibility: Compatibility) throws {
        let generator = UUID.TimestampGenerator()
        let ids = try (0..<100_000).map { _ in try generator.next(.now, compatibility: compatibility) }
        #expect(outOfOrderCount(ids) == 0)
    }

    @Test("Lossless stays exact while the counter runs")
    func losslessStaysExact() throws {
        let generator = UUID.TimestampGenerator()
        for _ in 0..<10_000 {
            let now = Date.now
            #expect(try generator.next(now, compatibility: .lossless).date(compatibility: .lossless) == now)
        }
        for _ in 0..<1_000 {
            #expect(try generator.next(sampleDate, compatibility: .lossless).date(compatibility: .lossless) == sampleDate)
        }
    }

    @Test("A clock step backward keeps the true time")
    func clockStepBackward() throws {
        let generator = UUID.TimestampGenerator()
        let later = sampleDate.addingTimeInterval(1)
        let first = try generator.next(later, compatibility: .lossless)
        let second = try generator.next(sampleDate, compatibility: .lossless)
        #expect(second.date(compatibility: .lossless) == sampleDate)
        #expect(second.uuidString < first.uuidString)
    }

    @Test("Concurrent use produces unique IDs")
    func concurrentUnique() async throws {
        let generator = UUID.TimestampGenerator()
        let ids = try await withThrowingTaskGroup(of: [UUID].self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try (0..<10_000).map { _ in try generator.next(compatibility: .lossless) }
                }
            }
            return try await group.reduce(into: []) { $0 += $1 }
        }
        #expect(Set(ids).count == 80_000)
    }
}
