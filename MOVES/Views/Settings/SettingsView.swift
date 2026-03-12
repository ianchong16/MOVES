import SwiftUI

// MARK: - Settings View
// Not a junk drawer. Clean rows, hairline dividers, monospaced labels.
// More like a terms page on a fashion site than an iOS settings screen.
// No list style — custom layout, full control.

struct SettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Text("SETTINGS")
                    .font(MOVESTypography.monoSmall())
                    .kerning(3)
                    .foregroundStyle(Color.movesGray300)
                    .padding(.top, MOVESSpacing.xl)

                Text("Settings")
                    .font(MOVESTypography.largeTitle())
                    .foregroundStyle(Color.movesPrimaryText)
                    .padding(.top, MOVESSpacing.xs)

                // Profile section
                sectionHeader("PROFILE")

                settingsRow(title: "Edit Taste Profile")
                settingsRow(title: "Location Settings")

                // Subscription section
                sectionHeader("SUBSCRIPTION")

                Button {
                    appState.showingPaywall = true
                } label: {
                    settingsRow(
                        title: appState.isPremium ? "Premium Active" : "Upgrade to Premium",
                        detail: appState.isPremium ? "Manage" : nil
                    )
                }
                .buttonStyle(.plain)

                // About section
                sectionHeader("ABOUT")

                settingsRow(title: "Privacy Policy")
                settingsRow(title: "Terms of Service")
                settingsRow(title: "Contact")

                // Version
                HStack {
                    Text("Version")
                        .font(MOVESTypography.body())
                        .foregroundStyle(Color.movesGray400)
                    Spacer()
                    Text("1.0.0")
                        .font(MOVESTypography.mono())
                        .foregroundStyle(Color.movesGray300)
                }
                .padding(.vertical, MOVESSpacing.md)
                .padding(.top, MOVESSpacing.xl)
            }
            .padding(.horizontal, MOVESSpacing.screenH)
            .padding(.bottom, MOVESSpacing.xxxl)
        }
        .background(Color.movesPrimaryBg)
    }

    // MARK: - Section Header
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(MOVESTypography.monoSmall())
            .kerning(2)
            .foregroundStyle(Color.movesGray300)
            .padding(.top, MOVESSpacing.xl)
            .padding(.bottom, MOVESSpacing.sm)
    }

    // MARK: - Settings Row
    // Hairline-separated rows. No icons. Just text + optional detail.
    private func settingsRow(title: String, detail: String? = nil) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(MOVESTypography.body())
                    .foregroundStyle(Color.movesPrimaryText)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(MOVESTypography.mono())
                        .foregroundStyle(Color.movesGray300)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.movesGray300)
            }
            .padding(.vertical, MOVESSpacing.md)

            Rectangle()
                .fill(Color.movesGray100)
                .frame(height: 0.5)
        }
    }
}
