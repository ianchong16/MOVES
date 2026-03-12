import SwiftUI

// MARK: - Paywall View
// Tasteful, not aggressive. Earned placement.
// SSENSE product page energy — the "product" is the subscription.
// Black and white. Monospaced metadata. Square everything.

struct PaywallView: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void = {}

    @State private var selectedPlan: PaywallPlan = .annual

    var body: some View {
        VStack(spacing: 0) {
            // Close bar
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Text("CLOSE")
                        .font(MOVESTypography.monoSmall())
                        .kerning(2)
                        .foregroundStyle(Color.movesGray400)
                        .padding(.vertical, MOVESSpacing.md)
                }
            }
            .padding(.horizontal, MOVESSpacing.screenH)
            .padding(.top, MOVESSpacing.sm)

            // Hairline
            Rectangle()
                .fill(Color.movesGray100)
                .frame(height: 0.5)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero copy
                    VStack(spacing: MOVESSpacing.md) {
                        Text("PREMIUM")
                            .font(MOVESTypography.monoSmall())
                            .kerning(3)
                            .foregroundStyle(Color.movesGray300)

                        Text("Get better moves.")
                            .font(MOVESTypography.largeTitle())
                            .foregroundStyle(Color.movesPrimaryText)
                            .multilineTextAlignment(.center)

                        Text("Less scrolling.\nMore living.")
                            .font(MOVESTypography.serif())
                            .foregroundStyle(Color.movesGray400)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, MOVESSpacing.xxl)

                    // Features — just text, no icons
                    VStack(alignment: .leading, spacing: 0) {
                        premiumFeature("Unlimited moves, every day")
                        premiumFeature("Remix endlessly until it clicks")
                        premiumFeature("Date night, group, creative modes")
                        premiumFeature("Hidden gems & neighborhood guides")
                        premiumFeature("Full move journal & photo archive")
                        premiumFeature("\"Surprise me harder\" mode")
                    }
                    .padding(.top, MOVESSpacing.xl)

                    // Hairline
                    Rectangle()
                        .fill(Color.movesGray100)
                        .frame(height: 0.5)
                        .padding(.top, MOVESSpacing.xl)

                    // Plan selector
                    VStack(spacing: 0) {
                        ForEach(PaywallPlan.allCases) { plan in
                            planRow(plan)
                        }
                    }
                    .padding(.top, MOVESSpacing.lg)

                    // CTA
                    MOVESPrimaryButton(title: "Start Premium") {
                        // StoreKit purchase — Phase 6
                        appState.isPremium = true
                        onDismiss()
                    }
                    .padding(.top, MOVESSpacing.xl)

                    // Fine print
                    VStack(spacing: MOVESSpacing.sm) {
                        Text("Cancel anytime. No commitment.")
                            .font(MOVESTypography.caption())
                            .foregroundStyle(Color.movesGray300)
                        MOVESTextButton(title: "Restore Purchases") {
                            // StoreKit restore — Phase 6
                        }
                    }
                    .padding(.top, MOVESSpacing.lg)
                }
                .padding(.horizontal, MOVESSpacing.screenH)
                .padding(.bottom, MOVESSpacing.xxxl)
            }
        }
        .background(Color.movesPrimaryBg)
    }

    // MARK: - Premium Feature Row
    // Simple: dash + text. No checkmarks, no icons. SSENSE product detail energy.
    private func premiumFeature(_ text: String) -> some View {
        HStack(alignment: .top, spacing: MOVESSpacing.md) {
            Text("—")
                .font(MOVESTypography.caption())
                .foregroundStyle(Color.movesGray300)
            Text(text)
                .font(MOVESTypography.body())
                .foregroundStyle(Color.movesPrimaryText)
        }
        .padding(.vertical, MOVESSpacing.sm)
    }

    // MARK: - Plan Row
    // No card border. Just content + selection indicator. Hairline between rows.
    private func planRow(_ plan: PaywallPlan) -> some View {
        Button {
            withAnimation(MOVESAnimation.quick) {
                selectedPlan = plan
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: MOVESSpacing.sm) {
                        Text(plan.title)
                            .font(MOVESTypography.headline())
                            .foregroundStyle(Color.movesPrimaryText)
                        if plan == .annual {
                            Text("BEST")
                                .font(MOVESTypography.monoSmall())
                                .kerning(1.5)
                                .foregroundStyle(Color.movesWhite)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.movesBlack)
                        }
                    }
                    Text(plan.subtitle)
                        .font(MOVESTypography.caption())
                        .foregroundStyle(Color.movesGray400)
                }
                Spacer()
                Text(plan.price)
                    .font(MOVESTypography.headline())
                    .foregroundStyle(Color.movesPrimaryText)

                // Selection indicator — square, not circle
                Rectangle()
                    .fill(selectedPlan == plan ? Color.movesBlack : Color.clear)
                    .overlay(
                        Rectangle()
                            .stroke(selectedPlan == plan ? Color.clear : Color.movesGray200, lineWidth: 1)
                    )
                    .overlay(
                        selectedPlan == plan ?
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.movesWhite)
                        : nil
                    )
                    .frame(width: 20, height: 20)
                    .padding(.leading, MOVESSpacing.sm)
            }
            .padding(.vertical, MOVESSpacing.md)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.movesGray100)
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Paywall Plan

enum PaywallPlan: String, CaseIterable, Identifiable {
    case annual = "Annual"
    case monthly = "Monthly"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .annual: return "Annual"
        case .monthly: return "Monthly"
        }
    }

    var price: String {
        switch self {
        case .annual: return "$39.99/yr"
        case .monthly: return "$6.99/mo"
        }
    }

    var subtitle: String {
        switch self {
        case .annual: return "$3.33/month — save 52%"
        case .monthly: return "Billed monthly"
        }
    }
}
