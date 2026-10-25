import Foundation
import Synchronization

extension UUID {
    /// How a `Date` is packed into the 122 non-version, non-variant bits of a UUID v7.
    ///
    /// Every option writes the RFC 9562 48-bit Unix millisecond field, so any v7 parser
    /// reads the correct millisecond. They differ in how much of the remaining space
    /// carries sub-millisecond time instead of randomness.
    public enum TimestampCompatibility: String, Sendable, CaseIterable {
        /// Strict RFC 9562: 48-bit milliseconds only.
        case milliseconds
        /// RFC 9562 Section 6.2 Method 3: 48-bit milliseconds plus a 12-bit fraction of the
        /// millisecond in `rand_a` (1/4096 steps, about 244 ns).
        case subMillisecond
        /// 48-bit milliseconds plus a 14-bit index of the `Date`'s exact binary tick within
        /// that millisecond (`rand_a` plus the top 2 bits of `rand_b`).
        ///
        /// Round-trips a `Date` bit for bit when its value is a multiple of 2⁻²³ seconds
        /// since the reference date, which holds for every `Date` from 2018 onward.
        case lossless

        /// The number of payload bits that carry time.
        var timeBits: Int {
            switch self {
            case .milliseconds: 48
            case .subMillisecond: 60
            case .lossless: 62
            }
        }
    }

    /// Whether UUIDs created with identical time bits keep their creation order.
    public enum TimestampOrdering: Sendable {
        /// The 28 bits after the time carry a counter. When the time bits repeat, the counter
        /// increments, so UUIDs from one generator sort in creation order. When the time
        /// advances, the counter restarts at a random value below 2²⁷.
        case monotonic
        /// Every bit after the time is random. UUIDs with identical time bits sort randomly.
        case unordered
    }

    public enum TimestampError: Error, Equatable {
        /// The date is before 1970 or after the 48-bit millisecond field runs out (year 10889).
        case outOfRange
        /// `.lossless` was requested for a date with precision finer than 2⁻²³ seconds.
        case notLosslesslyRepresentable
        /// More than 2²⁷ UUIDs shared the same time bits.
        case counterOverflow
    }

    /// Creates a UUID v7 whose time fields encode `date`.
    ///
    /// With `.monotonic` ordering this uses ``TimestampGenerator/shared``.
    public static func timestamp(
        _ date: Date = .now,
        compatibility: TimestampCompatibility = .subMillisecond,
        ordering: TimestampOrdering = .monotonic
    ) throws(TimestampError) -> UUID {
        switch ordering {
        case .monotonic:
            return try TimestampGenerator.shared.next(date, compatibility: compatibility)
        case .unordered:
            let timeField = try Self.timeField(for: date, compatibility: compatibility)
            return UUID(timeField: timeField, compatibility: compatibility, counter: nil)
        }
    }

    /// Decodes the date from a UUID v7 written with the given compatibility.
    ///
    /// Returns `nil` when the UUID is not version 7 with the RFC 9562 variant.
    public func date(compatibility: TimestampCompatibility) -> Date? {
        let value = bytes.reduce(UInt128(0)) { $0 << 8 | UInt128($1) }
        let version: UInt128 = value >> 76 & 0xF
        let variant: UInt128 = value >> 62 & 0b11
        guard version == 7, variant == 0b10 else { return nil }

        let high: UInt128 = value >> 80
        let middle: UInt128 = value >> 64 & 0xFFF
        let low: UInt128 = value & Self.mask(62)
        let payload: UInt128 = high << 74 | middle << 62 | low
        let timeField = UInt64(payload >> (Self.payloadBits - compatibility.timeBits))

        switch compatibility {
        case .milliseconds:
            let referenceMilliseconds = Int64(timeField) - Self.referenceOffsetMilliseconds
            return Date(timeIntervalSinceReferenceDate: Double(referenceMilliseconds) / 1000)
        case .subMillisecond:
            let referenceMilliseconds = Int64(timeField >> 12) - Self.referenceOffsetMilliseconds
            let fraction = Double(timeField & 0xFFF) / 4096
            return Date(timeIntervalSinceReferenceDate: (Double(referenceMilliseconds) + fraction) / 1000)
        case .lossless:
            let unixTicks = Self.firstTick(ofMillisecond: Int128(timeField >> 14)) + Int128(timeField & 0x3FFF)
            let referenceTicks = unixTicks - Self.referenceOffsetTicks
            return Date(timeIntervalSinceReferenceDate: Double(referenceTicks) * Self.tick)
        }
    }

    private var bytes: [UInt8] {
        withUnsafeBytes(of: uuid) { Array($0) }
    }
}

// MARK: - Generator

extension UUID {
    /// Creates time-ordered UUID v7 values that keep their creation order.
    ///
    /// Each generator remembers the time bits and counter of the last UUID it made for each
    /// compatibility option. It is safe to share across threads.
    public final class TimestampGenerator: Sendable {
        /// The generator used by `UUID.timestamp(_:compatibility:ordering:)`.
        public static let shared = TimestampGenerator()

        private struct Last {
            var timeField: UInt64
            var counter: UInt64
        }

        private let state = Mutex<[TimestampCompatibility: Last]>([:])

        public init() {}

        /// Creates the next UUID for `date`.
        ///
        /// When the time bits match the previous UUID's, the counter increments. When they
        /// are later, or earlier because the clock moved back, the counter restarts. The
        /// time is never altered, so `.lossless` stays exact; after a clock step backward,
        /// new UUIDs sort by their true time.
        public func next(
            _ date: Date = .now,
            compatibility: TimestampCompatibility = .subMillisecond
        ) throws(TimestampError) -> UUID {
            let timeField = try UUID.timeField(for: date, compatibility: compatibility)
            let counter = try state.withLock { (last) throws(TimestampError) -> UInt64 in
                var counter = UInt64.random(in: 0..<(1 << (UUID.counterBits - 1)))
                if let previous = last[compatibility], previous.timeField == timeField {
                    guard previous.counter < (1 << UUID.counterBits) - 1 else { throw .counterOverflow }
                    counter = previous.counter + 1
                }
                last[compatibility] = Last(timeField: timeField, counter: counter)
                return counter
            }
            return UUID(timeField: timeField, compatibility: compatibility, counter: counter)
        }
    }
}

// MARK: - Encoding

extension UUID {
    /// Seconds between 1970-01-01 and 2001-01-01, the `Date` reference date.
    private static let referenceOffsetSeconds: Int64 = 978_307_200
    private static let referenceOffsetMilliseconds = referenceOffsetSeconds * 1000
    private static let maxMilliseconds: UInt64 = 1 << 48 - 1

    /// The binary tick used by `.lossless`: 2⁻²³ seconds, the spacing of `Double`
    /// values for dates between 2018 and 2035.
    private static let tick: Double = 0x1p-23
    private static let ticksPerSecondShift = 23
    private static let referenceOffsetTicks = Int128(referenceOffsetSeconds) << ticksPerSecondShift

    /// Bits of a UUID that are neither version nor variant.
    fileprivate static let payloadBits = 122
    fileprivate static let counterBits = 28

    /// A value with the low `bits` bits set.
    fileprivate static func mask(_ bits: Int) -> UInt128 {
        (1 << bits) - 1
    }

    /// The time bits for `date`, right-aligned.
    fileprivate static func timeField(for date: Date, compatibility: TimestampCompatibility) throws(TimestampError) -> UInt64 {
        switch compatibility {
        case .milliseconds:
            return try splitMilliseconds(date).milliseconds
        case .subMillisecond:
            let split = try splitMilliseconds(date)
            return split.milliseconds << 12 | UInt64(min(UInt16(split.fraction * 4096), 0x0FFF))
        case .lossless:
            let split = try splitTicks(date)
            return split.milliseconds << 14 | UInt64(split.tickIndex)
        }
    }

    /// Splits a date into whole Unix milliseconds (floored) and the fraction of the next millisecond.
    private static func splitMilliseconds(_ date: Date) throws(TimestampError) -> (milliseconds: UInt64, fraction: Double) {
        // Work from the reference date. `timeIntervalSince1970` adds a constant in
        // floating point and loses the lowest bit for current dates.
        let interval = date.timeIntervalSinceReferenceDate
        guard interval.isFinite else { throw .outOfRange }
        let wholeSeconds = interval.rounded(.down)
        let scaledFraction = (interval - wholeSeconds) * 1000
        let wholeMilliseconds = scaledFraction.rounded(.down)
        guard let seconds = Int64(exactly: wholeSeconds) else { throw .outOfRange }

        let unixMilliseconds = (seconds + referenceOffsetSeconds) * 1000 + Int64(wholeMilliseconds)
        guard unixMilliseconds >= 0, UInt64(unixMilliseconds) <= maxMilliseconds else { throw .outOfRange }
        return (UInt64(unixMilliseconds), scaledFraction - wholeMilliseconds)
    }

    /// Splits a date into whole Unix milliseconds and the index of its exact tick within that millisecond.
    private static func splitTicks(_ date: Date) throws(TimestampError) -> (milliseconds: UInt64, tickIndex: UInt16) {
        let interval = date.timeIntervalSinceReferenceDate
        guard interval.isFinite else { throw .outOfRange }
        guard let referenceTicks = Int128(exactly: interval * 0x1p23) else {
            throw .notLosslesslyRepresentable
        }

        let unixTicks = referenceTicks + referenceOffsetTicks
        guard unixTicks >= 0 else { throw .outOfRange }
        let milliseconds = (unixTicks * 1000) >> ticksPerSecondShift
        guard milliseconds <= Int128(maxMilliseconds) else { throw .outOfRange }

        // At most ⌈2²³ / 1000⌉ = 8389 ticks fall in one millisecond, which fits in 14 bits.
        let tickIndex = unixTicks - firstTick(ofMillisecond: milliseconds)
        return (UInt64(milliseconds), UInt16(tickIndex))
    }

    /// The first tick at or after the start of the given Unix millisecond.
    private static func firstTick(ofMillisecond milliseconds: Int128) -> Int128 {
        ((milliseconds << ticksPerSecondShift) + 999) / 1000
    }

    /// Lays out the 122-bit payload as time, then the counter if any, then random bits,
    /// and inserts the version and variant.
    fileprivate init(timeField: UInt64, compatibility: TimestampCompatibility, counter: UInt64?) {
        var generator = SystemRandomNumberGenerator()
        let random = UInt128(generator.next() as UInt64) << 64 | UInt128(generator.next() as UInt64)

        let randomBits = Self.payloadBits - compatibility.timeBits
        var payload: UInt128 = UInt128(timeField) << randomBits | random & Self.mask(randomBits)
        if let counter {
            let counterShift = randomBits - Self.counterBits
            let counterMask: UInt128 = Self.mask(Self.counterBits) << counterShift
            payload = payload & ~counterMask | UInt128(counter) << counterShift
        }

        let high: UInt128 = payload >> 74
        let middle: UInt128 = payload >> 62 & 0xFFF
        let low: UInt128 = payload & Self.mask(62)
        let value: UInt128 = high << 80 | 0x7 << 76 | middle << 64 | 0b10 << 62 | low
        let byte = { (index: Int) in UInt8(truncatingIfNeeded: value >> (120 - 8 * index)) }
        self.init(uuid: (
            byte(0), byte(1), byte(2), byte(3), byte(4), byte(5), byte(6), byte(7),
            byte(8), byte(9), byte(10), byte(11), byte(12), byte(13), byte(14), byte(15)
        ))
    }
}
