import SwiftUI

// MARK: - Primary Button
// Full-width black rectangle. No rounded corners. SSENSE checkout energy.
// Text: uppercase, tracked, light weight. The button does the talking.

struct MOVESPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(.movesWhite)
                } else {
                    Text(title)
                        .font(MOVESTypography.caption())
                        .kerning(2.5)
                        .textCase(.uppercase)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.movesBlack)
            .foregroundStyle(Color.movesWhite)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Secondary Button
// Hairline border. No fill. Square.

struct MOVESSecondaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MOVESSpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                Text(title)
                    .font(MOVESTypography.caption())
                    .kerning(2)
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .overlay(
                Rectangle()
                    .stroke(Color.movesGray200, lineWidth: 1)
            )
            .foregroundStyle(Color.movesPrimaryText)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Text Button
// Bare text. Underlined. Nothing else.

struct MOVESTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(MOVESTypography.caption())
                .kerning(1)
                .foregroundStyle(Color.movesGray400)
                .underline()
        }
        .buttonStyle(.plain)
    }
}

#Preview("Buttons") {
    VStack(spacing: 20) {
        MOVESPrimaryButton(title: "Make a Move") {}
        MOVESPrimaryButton(title: "Loading", isLoading: true) {}
        MOVESSecondaryButton(title: "Save", icon: "bookmark") {}
        MOVESSecondaryButton(title: "Remix", icon: "arrow.triangle.2.circlepath") {}
        MOVESTextButton(title: "Skip for now") {}
    }
    .padding(28)
    .background(Color.movesPrimaryBg)
}
