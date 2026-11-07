@testable import RadioDirectory
import Testing

struct SequenceUniquedTests {
    @Test func `keeps the first element for each key, in order`() {
        let names = ["KEXP", "kexp", "WFMU", "Kexp", "wfmu", "KCRW"]
        #expect(names.uniqued { $0.lowercased() } == ["KEXP", "WFMU", "KCRW"])
    }

    @Test func `an empty sequence stays empty`() {
        #expect([String]().uniqued { $0 }.isEmpty)
    }
}
