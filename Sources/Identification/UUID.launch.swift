import Foundation

extension UUID {
    /// A UUID created once per process launch.
    ///
    /// It is a `UUID.timestamp`, so `Date(from: .launch)` returns the moment it was first read.
    public static let launch: UUID = UUID.timestamp
}
