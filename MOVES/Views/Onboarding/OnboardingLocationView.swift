import SwiftUI
import CoreLocation

// MARK: - Location Permission Screen (Onboarding Step 4)
// Square icon. Stark copy. Trust-building.

struct OnboardingLocationView: View {
    var locationService: LocationService
    @State private var showContent = false
    @State private var hasRequestedPermission = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: MOVESSpacing.xl) {
                // Square icon — not a circle. Brutalist.
                Rectangle()
                    .fill(Color.movesBlack)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "location")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(Color.movesWhite)
                    )
                    .opacity(showContent ? 1 : 0)

                VStack(spacing: MOVESSpacing.md) {
                    Text("Where are you\nright now?")
                        .font(MOVESTypography.largeTitle())
                        .foregroundStyle(Color.movesPrimaryText)
                        .multilineTextAlignment(.center)

                    Text("We check your location only when\nyou ask for a move. Never in the background.")
                        .font(MOVESTypography.caption())
                        .foregroundStyle(Color.movesGray400)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .opacity(showContent ? 1 : 0)
            }

            Spacer()

            locationStatus
                .opacity(showContent ? 1 : 0)
        }
        .padding(.horizontal, MOVESSpacing.screenH)
        .onAppear {
            withAnimation(MOVESAnimation.slow.delay(0.2)) {
                showContent = true
            }
        }
    }

    @ViewBuilder
    private var locationStatus: some View {
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            HStack(spacing: MOVESSpacing.sm) {
                Text("LOCATION ENABLED")
                    .font(MOVESTypography.monoSmall())
                    .kerning(2)
                    .foregroundStyle(Color.movesPrimaryText)
            }

        case .denied, .restricted:
            VStack(spacing: MOVESSpacing.sm) {
                Text("Location access was denied.")
                    .font(MOVESTypography.caption())
                    .foregroundStyle(Color.movesGray400)
                Text("You can enable it later in Settings.")
                    .font(MOVESTypography.caption())
                    .foregroundStyle(Color.movesGray300)
            }

        default:
            if !hasRequestedPermission {
                VStack(spacing: MOVESSpacing.md) {
                    MOVESPrimaryButton(title: "Enable Location") {
                        hasRequestedPermission = true
                        locationService.requestPermission()
                    }
                }
            } else {
                ProgressView()
                    .tint(Color.movesGray300)
            }
        }
    }
}
