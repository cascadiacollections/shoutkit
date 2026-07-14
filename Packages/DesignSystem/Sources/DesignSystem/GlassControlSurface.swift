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
            if #available(iOS 26.0, *) {
                content
                    .padding(ShoutKitSpacing.small)
                    .glassEffect(.regular, in: shape)
            } else {
                content
                    .padding(ShoutKitSpacing.small)
                    .background(.regularMaterial, in: shape)
                    .overlay {
                        shape.stroke(.primary.opacity(0.18), lineWidth: 1)
                    }
            }
        }
    }
}

public struct GlassActionCluster<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder
    public var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: ShoutKitSpacing.small) {
                content
            }
        } else {
            content
        }
    }
}

public extension View {
    @ViewBuilder
    func shoutKitGlassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func shoutKitGlassProminentButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    GlassControlSurface {
        HStack(spacing: ShoutKitSpacing.small) {
            Button {} label: {
                Label("Play", systemImage: "play.fill")
            }
            .modifier(PreviewGlassProminentStyle())

            Button {} label: {
                Label("Favorite", systemImage: "heart")
            }
            .modifier(PreviewGlassStyle())
        }
    }
    .padding()
}

private struct PreviewGlassProminentStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.shoutKitGlassProminentButtonStyle()
    }
}

private struct PreviewGlassStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.shoutKitGlassButtonStyle()
    }
}
