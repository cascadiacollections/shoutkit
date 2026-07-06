import SwiftUI

public struct GlassControlSurface<ShapeStyle: Shape, Content: View>: View {
    private let shape: ShapeStyle
    private let content: Content

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        in shape: ShapeStyle = Capsule(),
        @ViewBuilder content: () -> Content
    ) {
        self.shape = shape
        self.content = content()
    }

    public var body: some View {
        if reduceTransparency || colorSchemeContrast == .increased {
            content
                .padding(ShoutKitSpacing.small)
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.stroke(.primary.opacity(0.18), lineWidth: 1)
                }
        } else {
            content
                .padding(ShoutKitSpacing.small)
                .glassEffect(.regular, in: shape)
        }
    }
}

public struct GlassActionCluster<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        GlassEffectContainer(spacing: ShoutKitSpacing.small) {
            content
        }
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
