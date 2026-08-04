import SwiftUI

public extension View {
    /// Liquid Glass where the platform allows it; an opaque material plus a
    /// hairline border where the user has asked for less transparency or more
    /// contrast.
    ///
    /// One place makes that call, so every glass control in the app degrades
    /// identically. `StationRow`'s play affordance used to carry its own copy of
    /// this branch, with a comment promising it matched `GlassControlSurface` —
    /// the kind of promise that quietly stops being true.
    func glassControlBackground(in shape: some Shape) -> some View {
        modifier(GlassControlBackground(shape: shape))
    }
}

private struct GlassControlBackground<ClipShape: Shape>: ViewModifier {
    let shape: ClipShape

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency || colorSchemeContrast == .increased {
            content
                .background(.regularMaterial, in: shape)
                .overlay { shape.stroke(.primary.opacity(0.18), lineWidth: 1) }
        } else {
            content
                .glassEffect(.regular, in: shape)
        }
    }
}

/// A padded glass tray for a cluster of controls — a floating banner, an action
/// row, anything that has to read against arbitrary content behind it.
public struct GlassControlSurface<ClipShape: Shape, Content: View>: View {
    private let shape: ClipShape
    private let content: Content

    public init(
        in shape: ClipShape = Capsule(),
        @ViewBuilder content: () -> Content
    ) {
        self.shape = shape
        self.content = content()
    }

    public var body: some View {
        content
            .padding(ShoutKitSpacing.small)
            .glassControlBackground(in: shape)
    }
}

#Preview {
    GlassControlSurface {
        HStack(spacing: ShoutKitSpacing.small) {
            Button {} label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(.glassProminent)

            Button {} label: {
                Label("Favorite", systemImage: "heart")
            }
            .buttonStyle(.glass)
        }
    }
    .padding()
}
