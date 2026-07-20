import Testing
@testable import RadioDirectory

struct StationNameFormatterTests {
    @Test func underscoresBecomeSpaces() {
        #expect(StationNameFormatter.normalize("Radio_Swiss_Jazz") == "Radio Swiss Jazz")
    }

    @Test func bracketedClutterIsStripped() {
        #expect(StationNameFormatter.normalize("KEXP [HD]") == "KEXP")
        #expect(StationNameFormatter.normalize("Radio X (128k)") == "Radio X")
    }

    @Test func mismatchedBracketPairsAreLeftAlone() {
        #expect(StationNameFormatter.normalize("Radio (Foo]") == "Radio (Foo]")
    }

    @Test func whitespaceRunsCollapse() {
        #expect(StationNameFormatter.normalize("Classic   Rock_101") == "Classic Rock 101")
    }

    @Test func cleanNameIsUnchanged() {
        #expect(StationNameFormatter.normalize("KEXP 90.3 Seattle, WA") == "KEXP 90.3 Seattle, WA")
    }
}
