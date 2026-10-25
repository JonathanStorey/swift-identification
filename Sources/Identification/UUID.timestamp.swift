import Foundation
import Synchronization

extension UUID {
    public enum TimestampError: Error, Equatable {
        /// The date is before 1970 or after the 48-bit millisecond field runs out (year 10889).
        case outOfRange
        /// The date has precision finer than 2⁻²³ seconds, which only happens before 2018.
        case notLosslesslyRepresentable
        /// More than 2²⁷ UUIDs shared the same timestamp.
        case counterOverflow
    }

    /// Creates a time-ordered UUID v7 that stores `date` exactly.
    ///
    /// The 122 payload bits are laid out as:
    /// - 48 bits: Unix milliseconds since 1970, as RFC 9562 requires.
    /// - 14 bits: the index of the `Date`'s exact 2⁻²³ s tick within that millisecond.
    /// - 28 bits: a counter that keeps UUIDs with the same timestamp in creation order.
    /// - 32 bits: random.
    ///
    /// `Date(from:)` returns the identical `Date` for any date from 2018 onward.
    public static func timestamp(_ date: Date = .now) throws(TimestampError) -> UUID {
        try TimestampGenerator.shared.next(date)
    }
}

// MARK: - Generator

/// Remembers the last timestamp and counter so that UUIDs keep their creation order.
///
/// When the timestamp repeats, the counter increments. When it changes, the counter restarts
/// at a random value below 2²⁷. The timestamp itself is never altered, so it stays exact;
/// after a clock step backward, new UUIDs sort by their true time.
final class TimestampGenerator: Sendable {
    static let shared = TimestampGenerator()

    private struct Last {
        var timestamp: UInt64
        var counter: UInt64
    }

    private let last = Mutex<Last?>(nil)

    func next(_ date: Date = .now) throws(UUID.TimestampError) -> UUID {
        let timestamp = try UUID.timestampField(for: date)
        let counter = try last.withLock { (last) throws(UUID.TimestampError) -> UInt64 in
            var counter = UInt64.random(in: 0..<(1 << (UUID.counterBits - 1)))
            if let previous = last, previous.timestamp == timestamp {
                guard previous.counter < (1 << UUID.counterBits) - 1 else { throw .counterOverflow }
                counter = previous.counter + 1
            }
            last = Last(timestamp: timestamp, counter: counter)
            return counter
        }
        return UUID(timestamp: timestamp, counter: counter)
    }
}

// MARK: - Layout

extension UUID {
    /// Seconds between 1970-01-01 and 2001-01-01, the `Date` reference date.
    static let referenceOffsetSeconds: Int64 = 978_307_200
    static let maxMilliseconds: UInt64 = 1 << 48 - 1

    /// One tick is 2⁻²³ seconds, the spacing of `Double` values for dates between 2018 and 2035.
    static let ticksPerSecondShift = 23
    static let referenceOffsetTicks = Int128(referenceOffsetSeconds) << ticksPerSecondShift

    static let millisecondBits = 48
    static let tickIndexBits = 14
    static let timestampBits = millisecondBits + tickIndexBits
    static let counterBits = 28
    /// Bits of a UUID that are neither version nor variant.
    static let payloadBits = 122

    /// A value with the low `bits` bits set.
    static func mask(_ bits: Int) -> UInt128 {
        (1 << bits) - 1
    }

    /// The first tick at or after the start of the given Unix millisecond.
    static func firstTick(ofMillisecond milliseconds: Int128) -> Int128 {
        ((milliseconds << ticksPerSecondShift) + 999) / 1000
    }

    /// The 62-bit timestamp for `date`: Unix milliseconds, then the tick index within that millisecond.
    static func timestampField(for date: Date) throws(TimestampError) -> UInt64 {
        // Work from the reference date in integers. `timeIntervalSince1970` adds the offset
        // in floating point and loses the lowest bit for current dates.
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
        return UInt64(milliseconds) << tickIndexBits | UInt64(tickIndex)
    }

    /// The 122 payload bits with the version and variant removed.
    var payload: UInt128? {
        let value = withUnsafeBytes(of: uuid) { $0.reduce(UInt128(0)) { $0 << 8 | UInt128($1) } }
        let version: UInt128 = value >> 76 & 0xF
        let variant: UInt128 = value >> 62 & 0b11
        guard version == 7, variant == 0b10 else { return nil }

        let high: UInt128 = value >> 80
        let middle: UInt128 = value >> 64 & 0xFFF
        let low: UInt128 = value & Self.mask(62)
        return high << 74 | middle << 62 | low
    }

    /// Lays out the payload as timestamp, counter and random bits, and inserts the version and variant.
    init(timestamp: UInt64, counter: UInt64) {
        var generator = SystemRandomNumberGenerator()
        let randomBits = Self.payloadBits - Self.timestampBits - Self.counterBits
        let random = UInt128(generator.next() as UInt64) & Self.mask(randomBits)
        let payload: UInt128 = UInt128(timestamp) << (Self.payloadBits - Self.timestampBits)
            | UInt128(counter) << randomBits
            | random

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
