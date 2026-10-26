import Foundation

extension Date {
    /// Creates the date stored in a UUID made by `UUID.timestamp(_:)`.
    ///
    /// Returns `nil` when the UUID is not version 7, or when its tick index points past the end
    /// of its millisecond, which means another generator wrote those bits. A version 7 UUID
    /// from another library still decodes to the correct millisecond, with an arbitrary
    /// sub-millisecond part.
    public init?(from timestamp: UUID) {
        guard let payload = timestamp.payload else { return nil }
        let field = payload >> (UUID.payloadBits - UUID.timestampBits)
        let milliseconds = Int128(field >> UUID.tickIndexBits)
        let tickIndex = Int128(field & UUID.mask(UUID.tickIndexBits))

        let firstTick = UUID.firstTick(ofMillisecond: milliseconds)
        guard firstTick + tickIndex < UUID.firstTick(ofMillisecond: milliseconds + 1) else { return nil }

        let referenceTicks = firstTick + tickIndex - UUID.referenceOffsetTicks
        self.init(timeIntervalSinceReferenceDate: Double(referenceTicks) * 0x1p-23)
    }
}
