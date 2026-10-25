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
    @MainActor
    public static var vendor: UUID? {
        #if os(watchOS)
        WKInterfaceDevice.current().identifierForVendor
        #elseif canImport(UIKit)
        UIDevice.current.identifierForVendor
        #else
        AppStore.deviceVerificationID
        #endif
    }
}
#endif
