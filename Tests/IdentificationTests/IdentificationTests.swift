import Testing
@testable import Identification

@Suite("Identification")
struct IdentificationTests {
    @Test("Package exposes a version string")
    func versionIsNotEmpty() {
        #expect(!Identification.version.isEmpty)
    }
}
