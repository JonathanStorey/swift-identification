import Foundation
import Testing
@testable import Identification

@Suite("Identity UUIDs")
struct UUIDIdentityTests {
    @Test("Launch is stable within a process and records when it was created")
    func launch() throws {
        #expect(UUID.launch == UUID.launch)
        let date = try #require(Date(from: .launch))
        #expect(date <= .now)
    }

    @Test("Installation is created once and then read back")
    func installation() throws {
        let suite = "Identification.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = UUID.storedIdentifier(forKey: "installation", in: defaults)
        let second = UUID.storedIdentifier(forKey: "installation", in: defaults)
        #expect(first == second)
        #expect(Date(from: first) != nil)
        #expect(UUID.installation == UUID.installation)
    }

    @Test("Boot is available on macOS and Linux")
    func boot() throws {
        #if os(macOS) || os(Linux)
        let boot = try #require(UUID.boot)
        print("[identity] boot: \(boot)")
        #expect(UUID.boot == boot)
        #endif
    }

    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    @Test("Vendor is stable across reads")
    @MainActor
    func vendor() {
        print("[identity] vendor: \(String(describing: UUID.vendor))")
        #expect(UUID.vendor == UUID.vendor)
    }

    @Test("Persistent is stable across reads when the Keychain is available")
    func persistent() {
        // An unsigned test runner has no Keychain entitlement, so this is often nil in CI.
        print("[identity] persistent: \(String(describing: UUID.persistent))")
        if let id = UUID.persistent {
            #expect(UUID.persistent == id)
        }
    }
    #endif
}
