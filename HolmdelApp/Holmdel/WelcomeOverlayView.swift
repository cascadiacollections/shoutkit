import DesignSystem
import SwiftUI

/// One-time first-run overlay — not an onboarding carousel. A single screen
/// stating the app's core promise, shown once via `hasCompletedFirstRun`.
///
/// The genre row is part of that same screen. It scrolls sideways when the
/// phone is too narrow for six chips; it does not page, and Get Started is
/// always the way through. Leaving the selection empty keeps today's popular
/// stations.
struct WelcomeOverlayView: View {
    let onContinue: (FirstRunGenre?) -> Void

    private let preselected: FirstRunGenre?
    @State private var selection: FirstRunGenre?
    /// A tap owns the selection after this. A welcome link that arrives later
    /// must not overwrite a chip the listener already chose.
    @State private var didEditSelection = false

    init(
        preselected: FirstRunGenre? = nil,
        onContinue: @escaping (FirstRunGenre?) -> Void,
    ) {
        self.preselected = preselected
        self.onContinue = onContinue
        _selection = State(initialValue: preselected)
    }

    var body: some View {
        ZStack {
            background
            scrollingContent
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            continueButton
        }
        .onChange(of: preselected) { _, newValue in
            guard didEditSelection == false else { return }
            selection = newValue
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var background: some View {
        LinearGradient.shoutKitSpotlight
            .opacity(0.9)
            .ignoresSafeArea()
    }

    private var scrollingContent: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: ShoutKitSpacing.large) {
                    Spacer(minLength: ShoutKitSpacing.large)
                    header
                    genrePicker
                    Spacer(minLength: ShoutKitSpacing.large)
                }
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var header: some View {
        VStack(spacing: ShoutKitSpacing.large) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)

            VStack(spacing: ShoutKitSpacing.small) {
                Text("Welcome to ShoutKit")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Everything works without an account. Tap a station to start listening.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ShoutKitSpacing.large)
            }
        }
    }

    private var genrePicker: some View {
        VStack(alignment: .leading, spacing: ShoutKitSpacing.small) {
            Text("Pick a genre")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, ShoutKitSpacing.extraLarge)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ShoutKitSpacing.small) {
                    ForEach(FirstRunGenre.allCases) { genre in
                        genreChip(genre)
                    }
                }
                .padding(.horizontal, ShoutKitSpacing.extraLarge)
            }
        }
    }

    private var continueButton: some View {
        Button {
            onContinue(selection)
        } label: {
            Text("Get Started")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(.white)
        .foregroundStyle(Color.shoutKitAccent)
        .padding(.horizontal, ShoutKitSpacing.extraLarge)
        .padding(.bottom, ShoutKitSpacing.large)
    }

    @ViewBuilder
    private func genreChip(_ genre: FirstRunGenre) -> some View {
        let label = Text(verbatim: genre.directoryTag)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, ShoutKitSpacing.extraSmall)

        if selection == genre {
            Button {
                toggle(genre)
            } label: {
                label
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .foregroundStyle(Color.shoutKitAccent)
            .accessibilityLabel(Text(verbatim: genre.directoryTag))
            .accessibilityIdentifier(genreChipIdentifier(genre))
            .accessibilityAddTraits(.isSelected)
        } else {
            Button {
                toggle(genre)
            } label: {
                label
            }
            .buttonStyle(.glass)
            .foregroundStyle(.white)
            .accessibilityLabel(Text(verbatim: genre.directoryTag))
            .accessibilityIdentifier(genreChipIdentifier(genre))
        }
    }

    private func toggle(_ genre: FirstRunGenre) {
        didEditSelection = true
        selection = selection == genre ? nil : genre
    }

    private func genreChipIdentifier(_ genre: FirstRunGenre) -> String {
        "welcomeGenre.\(genre.rawValue)"
    }
}

#Preview("Seasonal") {
    WelcomeOverlayView(preselected: .christmas, onContinue: { _ in })
}

#Preview("No preset") {
    WelcomeOverlayView(onContinue: { _ in })
}
