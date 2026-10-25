import Foundation

extension UUID {
    /// The operating system's identifier for the current boot, or `nil` where none is available.
    ///
    /// It is shared by every process on the machine and changes on each restart. On Apple
    /// platforms it reads `kern.bootsessionuuid`; on Linux, `/proc/sys/kernel/random/boot_id`.
    public static let boot: UUID? = readBootIdentifier()

    private static func readBootIdentifier() -> UUID? {
        #if canImport(Darwin)
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return nil }
        let string = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return UUID(uuidString: string)
        #elseif os(Linux)
        guard let string = try? String(contentsOfFile: "/proc/sys/kernel/random/boot_id", encoding: .utf8) else { return nil }
        return UUID(uuidString: string.trimmingCharacters(in: .whitespacesAndNewlines))
        #else
        return nil
        #endif
    }
}
