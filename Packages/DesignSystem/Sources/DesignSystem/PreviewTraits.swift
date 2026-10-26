import SwiftUI

/// Preview canvases shared by every package's `#Preview`s.
///
/// The low-end profiling floor is an iPhone SE (2nd generation): 4.7", 375 × 667 pt,
/// a home button, no notch, no home indicator. It is the narrowest and shortest
/// screen the app supports on a phone, so a layout that holds there holds
/// everywhere — which is the point of naming it once here instead of scattering
/// `375`s through the previews.
public extension PreviewTrait where T == Preview.ViewTraits {
    /// The iPhone SE (2nd / 3rd generation) screen in points: 375 × 667.
    ///
    /// A fixed layout, not a device: the canvas reproduces the width and height
    /// but not the SE's 20 pt status-bar inset or its zero bottom inset. Pick an
    /// iPhone SE simulator as the preview device when safe-area behaviour is the
    /// question rather than horizontal room.
    static var iPhoneSE: PreviewTrait<Preview.ViewTraits> {
        .fixedLayout(width: 375, height: 667)
    }
}

public extension DynamicTypeSize {
    /// The Dynamic Type size the narrow-screen previews pair with ``PreviewTrait/iPhoneSE``:
    /// the third accessibility size, large enough that single-line text and
    /// fixed-width rows run out of room, without being the outlier the largest
    /// size is.
    static let narrowScreenPreview: DynamicTypeSize = .accessibility3
}
