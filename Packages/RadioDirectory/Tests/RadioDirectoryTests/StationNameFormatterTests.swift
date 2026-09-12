@testable import RadioDirectory
import Testing

struct StationNameFormatterTests {
    @Test func `underscores become spaces`() {
        #expect(StationNameFormatter.normalize("Radio_Swiss_Jazz") == "Radio Swiss Jazz")
    }

    @Test func `bracketed clutter is stripped`() {
        #expect(StationNameFormatter.normalize("KEXP [HD]") == "KEXP")
        #expect(StationNameFormatter.normalize("Radio X (128k)") == "Radio X")
    }

    @Test func `mismatched bracket pairs are left alone`() {
        #expect(StationNameFormatter.normalize("Radio (Foo]") == "Radio (Foo]")
    }

    @Test func `whitespace runs collapse`() {
        #expect(StationNameFormatter.normalize("Classic   Rock_101") == "Classic Rock 101")
    }

    @Test func `clean name is unchanged`() {
        #expect(StationNameFormatter.normalize("KEXP 90.3 Seattle, WA") == "KEXP 90.3 Seattle, WA")
    }
}
