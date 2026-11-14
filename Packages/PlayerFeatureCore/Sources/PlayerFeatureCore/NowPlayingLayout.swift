import Foundation

/// Which arrangement the Now Playing screen uses for the space it has.
///
/// The screen used to go side by side whenever it was wider than tall. That
/// holds on an iPhone in landscape, but a resizable window (iPad windowing,
/// iPhone Mirroring) can be only slightly wider than tall, and there the
/// artwork took most of the width: the overflow menu, the sleep timer and the
/// level meter ran off the trailing edge and the play/pause capsule collapsed
/// (#149). Side by side is now chosen only when the controls column it leaves
/// is still usable; otherwise the vertical stack, which scrolls, takes over.
public enum NowPlayingLayout: Equatable, Sendable {
    /// Artwork above the title, level meter and controls.
    case vertical
    /// Artwork beside a column holding the title, level meter and controls.
    case sideBySide

    /// The narrowest controls column side by side may leave. The transport row
    /// alone is two 44 pt circles and a play/pause capsule with 16 pt gaps,
    /// about 200 pt before the capsule stops reading as one; the rest keeps
    /// the station name from wrapping a word per line.
    public static let minimumControlsColumnWidth: CGFloat = 260

    /// The artwork's edge length when side by side: as tall as the space
    /// allows less room for the grabber and padding, within 120...220 pt.
    public static func sideBySideArtworkSize(height: CGFloat) -> CGFloat {
        min(220, max(120, height - 64))
    }

    /// Picks the arrangement for a container of `width` × `height`.
    ///
    /// - Parameters:
    ///   - isAccessibilitySize: accessibility Dynamic Type sizes always stack,
    ///     because the column cannot hold the larger text at any width.
    ///   - spacing: the screen's outer padding, also used as the gap between
    ///     artwork and column, so side by side spends three of them on the row.
    public static func choose(
        width: CGFloat,
        height: CGFloat,
        isAccessibilitySize: Bool,
        spacing: CGFloat,
    ) -> NowPlayingLayout {
        guard width > height, !isAccessibilitySize else { return .vertical }
        let columnWidth = width - sideBySideArtworkSize(height: height) - spacing * 3
        return columnWidth >= minimumControlsColumnWidth ? .sideBySide : .vertical
    }
}
