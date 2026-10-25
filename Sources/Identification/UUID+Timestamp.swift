import Foundation

extension UUID {
    /// How a `Date` is packed into the 74 non-version, non-variant bits of a UUID v7.
    ///
    /// Every option writes the RFC 9562 48-bit Unix millisecond field, so any v7 parser
    /// reads the correct millisecond. They differ in how much of the remaining space
    /// carries sub-millisecond time instead of randomness.
    public enum TimestampCompatibility: String, Sendable, CaseIterable {
        /// Strict RFC 9562: 48-bit milliseconds, `rand_a` and `rand_b` fully random (74 random bits).
        case milliseconds
        /// RFC 9562 Section 6.2 Method 3: `rand_a` holds the fraction of a millisecond
        /// in 1/4096 steps (about 244 ns). 62 random bits.
        case subMillisecond
        /// 48-bit milliseconds plus a 14-bit index of the `Date`'s exact binary tick within
        /// that millisecond (`rand_a` plus the top 2 bits of `rand_b`). 60 random bits.
        ///
        /// Round-trips a `Date` bit for bit when its value is a multiple of 2⁻²³ seconds
        /// since the reference date, which holds for every `Date` from 2018 onward.
        case lossless
    }

    public enum TimestampError: Error, Equatable {
        /// The date is before 1970 or after the 48-bit millisecond field runs out (year 10889).
        case outOfRange
        /// `.lossless` was requested for a date with precision finer than 2⁻²³ seconds.
        case notLosslesslyRepresentable
    }

    /// Creates a UUID v7 whose time fields encode `date`.
    public static func timestamp(
        _ date: Date = .now,
        compatibility: TimestampCompatibility = .subMillisecond
    ) throws(TimestampError) -> UUID {
        var generator = SystemRandomNumberGenerator()
        var randA = UInt16.random(in: 0...0x0FFF, using: &generator)
        var randB = UInt64.random(in: 0...(1 << 62 - 1), using: &generator)
        let milliseconds: UInt64

        switch compatibility {
        case .milliseconds:
            milliseconds = try Self.splitMilliseconds(date).milliseconds
        case .subMillisecond:
            let split = try Self.splitMilliseconds(date)
            milliseconds = split.milliseconds
            randA = min(UInt16(split.fraction * 4096), 0x0FFF)
        case .lossless:
            let split = try Self.splitTicks(date)
            milliseconds = split.milliseconds
            randA = UInt16(split.tickIndex >> 2)
            randB = (randB & (1 << 60 - 1)) | (UInt64(split.tickIndex & 0b11) << 60)
        }

        return UUID(milliseconds: milliseconds, randA: randA, randB: randB)
    }

    /// Decodes the date from a UUID v7 written with the given compatibility.
    ///
    /// Returns `nil` when the UUID is not version 7 with the RFC 9562 variant.
    public func date(compatibility: TimestampCompatibility) -> Date? {
        let bytes = withUnsafeBytes(of: uuid) { Array($0) }
        guard bytes[6] >> 4 == 7, bytes[8] >> 6 == 0b10 else { return nil }

        let milliseconds = bytes[0..<6].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let randA = UInt16(bytes[6] & 0x0F) << 8 | UInt16(bytes[7])
        let referenceMilliseconds = Int64(milliseconds) - Self.referenceOffsetMilliseconds

        switch compatibility {
        case .milliseconds:
            return Date(timeIntervalSinceReferenceDate: Double(referenceMilliseconds) / 1000)
        case .subMillisecond:
            let fraction = Double(randA) / 4096
            return Date(timeIntervalSinceReferenceDate: (Double(referenceMilliseconds) + fraction) / 1000)
        case .lossless:
            let tickIndex = Int128(randA) << 2 | Int128(bytes[8] >> 4 & 0b11)
            let unixTicks = Self.firstTick(ofMillisecond: Int128(milliseconds)) + tickIndex
            let referenceTicks = unixTicks - Self.referenceOffsetTicks
            return Date(timeIntervalSinceReferenceDate: Double(referenceTicks) * Self.tick)
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

    private init(milliseconds: UInt64, randA: UInt16, randB: UInt64) {
        self.init(uuid: (
            UInt8(truncatingIfNeeded: milliseconds >> 40),
            UInt8(truncatingIfNeeded: milliseconds >> 32),
            UInt8(truncatingIfNeeded: milliseconds >> 24),
            UInt8(truncatingIfNeeded: milliseconds >> 16),
            UInt8(truncatingIfNeeded: milliseconds >> 8),
            UInt8(truncatingIfNeeded: milliseconds),
            0x70 | UInt8(truncatingIfNeeded: randA >> 8 & 0x0F),
            UInt8(truncatingIfNeeded: randA),
            0x80 | UInt8(truncatingIfNeeded: randB >> 56 & 0x3F),
            UInt8(truncatingIfNeeded: randB >> 48),
            UInt8(truncatingIfNeeded: randB >> 40),
            UInt8(truncatingIfNeeded: randB >> 32),
            UInt8(truncatingIfNeeded: randB >> 24),
            UInt8(truncatingIfNeeded: randB >> 16),
            UInt8(truncatingIfNeeded: randB >> 8),
            UInt8(truncatingIfNeeded: randB)
        ))
    }
}
