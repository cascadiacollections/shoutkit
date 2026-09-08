import DesignSystem
import SwiftUI

/// One-time first-run overlay — not an onboarding carousel. A single screen
/// stating the app's core promise, shown once via `hasCompletedFirstRun`.
struct WelcomeOverlayView: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            LinearGradient.shoutKitSpotlight
                .opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: ShoutKitSpacing.large) {
                Spacer()

                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)

                VStack(spacing: ShoutKitSpacing.small) {
                    Text("Welcome to Holmdel")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Everything works without an account. Tap a station to start listening.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, ShoutKitSpacing.large)
                }

                Spacer()

                Button(action: onContinue) {
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
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

#Preview {
    WelcomeOverlayView(onContinue: {})
}
