import Foundation
@testable import PlayerFeatureCore
import Testing

struct NowPlayingLayoutTests {
    /// `ShoutKitSpacing.large`, the value the view passes.
    private let spacing: CGFloat = 24

    private func layout(_ width: CGFloat, _ height: CGFloat, accessibility: Bool = false) -> NowPlayingLayout {
        NowPlayingLayout.choose(width: width, height: height, isAccessibilitySize: accessibility, spacing: spacing)
    }

    @Test func `portrait stacks`() {
        #expect(layout(402, 874) == .vertical)
    }

    @Test func `iPhone landscape goes side by side`() {
        #expect(layout(874, 402) == .sideBySide)
    }

    /// The #149 case: a resizable window only slightly wider than tall. Side by
    /// side would leave a 116 pt column, so the controls ran off the edge.
    @Test func `a barely landscape window stacks instead of overflowing`() {
        #expect(layout(420, 380) == .vertical)
    }

    @Test func `a short wide window goes side by side`() {
        #expect(layout(1000, 400) == .sideBySide)
    }

    @Test func `accessibility text sizes always stack`() {
        #expect(layout(874, 402, accessibility: true) == .vertical)
    }

    /// The boundary: exactly the minimum column is enough.
    @Test func `the minimum column width is inclusive`() {
        let height: CGFloat = 300
        let width = NowPlayingLayout.sideBySideArtworkSize(height: height)
            + spacing * 3 + NowPlayingLayout.minimumControlsColumnWidth
        #expect(layout(width, height) == .sideBySide)
        #expect(layout(width - 1, height) == .vertical)
    }

    @Test(arguments: [(100.0, 120.0), (250.0, 186.0), (400.0, 220.0)])
    func `artwork is clamped to 120 through 220`(height: Double, expected: Double) {
        #expect(NowPlayingLayout.sideBySideArtworkSize(height: CGFloat(height)) == CGFloat(expected))
    }
}
