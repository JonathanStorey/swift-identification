import Foundation
#if os(watchOS)
import WatchKit
#elseif canImport(UIKit)
import UIKit
#elseif os(macOS)
import StoreKit
#endif

#if os(watchOS) || canImport(UIKit) || os(macOS)
extension UUID {
    /// The device identifier shared by all apps from the same developer, or `nil` before the
    /// device is first unlocked after a restart.
    ///
    /// It resets when the user deletes every app from that developer. On iOS, tvOS and visionOS
    /// this is `UIDevice.identifierForVendor`; on watchOS, `WKInterfaceDevice.identifierForVendor`;
    /// on macOS, the App Store's `deviceVerificationID`.
    ///
    /// The value is cached after the first non-`nil` read, since it cannot change while the app runs.
    @MainActor
    public static var vendor: UUID? {
        if let cachedVendor {
            return cachedVendor
        }
        #if os(watchOS)
        cachedVendor = WKInterfaceDevice.current().identifierForVendor
        #elseif canImport(UIKit)
        cachedVendor = UIDevice.current.identifierForVendor
        #else
        cachedVendor = AppStore.deviceVerificationID
        #endif
        return cachedVendor
    }

    @MainActor
    private static var cachedVendor: UUID?
}
#endif
