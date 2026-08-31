//
//  Atoms.swift
//  Sandbox
//
//  The small set of controls every screen is built from.
//

import SwiftUI

// MARK: - Buttons

struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    var loading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: { if enabled && !loading { action() } }) {
            ZStack {
                if loading {
                    ProgressView().tint(.white)
                } else {
                    Text(title).font(AppFont.medium(16))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(enabled ? AnyView(AppColors.primaryGradient) : AnyView(AppColors.surfaceRaised))
            .foregroundColor(enabled ? .white : AppColors.textDisabled)
            .cornerRadius(14)
        }
        .disabled(!enabled || loading)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.medium(16))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(AppColors.surfaceRaised)
                .foregroundColor(AppColors.textPrimary)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        }
    }
}

struct LinkButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.medium(14))
                .foregroundColor(AppColors.primary)
        }
    }
}

/// Google / Apple sign-in row.
struct SocialButton: View {
    let systemImage: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                Text(title).font(AppFont.medium(15))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(AppColors.surfaceRaised)
            .foregroundColor(AppColors.textPrimary)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        }
    }
}

// MARK: - Input

struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false
    var autocapitalization: TextInputAutocapitalization = .never
    var errorText: String?

    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Group {
                    if isSecure && !revealed {
                        SecureField("", text: $text, prompt: prompt)
                    } else {
                        TextField("", text: $text, prompt: prompt)
                    }
                }
                .font(AppFont.body(16))
                .foregroundColor(AppColors.textPrimary)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()

                if isSecure {
                    Button { revealed.toggle() } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(AppColors.surface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(errorText == nil ? AppColors.border : AppColors.error, lineWidth: 1)
            )

            if let errorText {
                Text(errorText)
                    .font(AppFont.caption())
                    .foregroundColor(AppColors.error)
                    .padding(.leading, 4)
            }
        }
    }

    private var prompt: Text {
        Text(placeholder).foregroundColor(AppColors.textDisabled)
    }
}

struct AppCheckbox: View {
    @Binding var checked: Bool
    let title: String

    var body: some View {
        Button { checked.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundColor(checked ? AppColors.primary : AppColors.textSecondary)
                Text(title)
                    .font(AppFont.body(14))
                    .foregroundColor(AppColors.textSecondary)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Rows

/// Tappable settings row that pushes another screen.
struct SettingsRow: View {
    let title: String
    var value: String?
    var icon: String?
    var showsChevron = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .frame(width: 22)
                        .foregroundColor(AppColors.primary)
                }
                Text(title)
                    .font(AppFont.body(15))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if let value {
                    Text(value)
                        .font(AppFont.body(14))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.textDisabled)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
        }
    }
}

/// Settings row backed by a boolean the SDK owns.
struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    var icon: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .frame(width: 22)
                    .foregroundColor(AppColors.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.body(15))
                    .foregroundColor(AppColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.caption(11))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppColors.primary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
    }
}

struct SectionCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(AppFont.caption(11))
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) { content }
                .background(AppColors.surface)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        }
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.border)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

// MARK: - Feedback

struct Loader: View {
    @Binding var show: Bool
    var message: String = ""

    var body: some View {
        if show {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().tint(.white).scaleEffect(1.3)
                    if !message.isEmpty {
                        Text(message)
                            .font(AppFont.body(14))
                            .foregroundColor(AppColors.textPrimary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(28)
                .background(AppColors.surfaceRaised)
                .cornerRadius(18)
            }
            .transition(.opacity)
        }
    }
}

struct AppAlertView: View {
    @Binding var shown: Bool
    var title: String?
    var message: String?
    var okTitle: String = "OK"
    var cancelTitle: String?
    /// Both are labeled at every call site. An unlabeled trailing closure here
    /// is ambiguous between the two, and Swift's forward and backward matching
    /// rules disagree about which one it means.
    var onOk: (() -> Void)?
    var onCancel: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                if let title {
                    Text(title)
                        .font(AppFont.heading(18))
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                }
                if let message {
                    Text(message)
                        .font(AppFont.body(14))
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 12) {
                    if let cancelTitle {
                        SecondaryButton(title: cancelTitle) {
                            shown = false
                            onCancel?()
                        }
                    }
                    PrimaryButton(title: okTitle) {
                        shown = false
                        onOk?()
                    }
                }
            }
            .padding(24)
            .background(AppColors.surfaceRaised)
            .cornerRadius(20)
            .padding(.horizontal, 32)
        }
    }
}

/// Coloured pill used for device state and event tags.
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(AppFont.caption(11))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .cornerRadius(6)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundColor(AppColors.textDisabled)
            Text(title)
                .font(AppFont.heading(18))
                .foregroundColor(AppColors.textPrimary)
            Text(message)
                .font(AppFont.body(14))
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, action: action)
                    .frame(maxWidth: 240)
                    .padding(.top, 8)
            }
        }
        .padding(32)
    }
}

// MARK: - Screen chrome

/// Background + safe-area padding every screen shares.
struct ScreenBackground<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AppColors.backgroundGradient.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
    }
}

struct NavBar: View {
    let title: String
    var onBack: (() -> Void)?
    var trailing: AnyView?

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(AppColors.surface)
                        .clipShape(Circle())
                }
            }
            Text(title)
                .font(AppFont.heading(18))
                .foregroundColor(AppColors.textPrimary)
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// Numbered step header used throughout the pairing flow.
struct StepHeader: View {
    let step: Int
    let total: Int
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STEP \(step) OF \(total)")
                .font(AppFont.caption(11))
                .foregroundColor(AppColors.primary)
            Text(title)
                .font(AppFont.title(26))
                .foregroundColor(AppColors.textPrimary)
            Text(subtitle)
                .font(AppFont.body(15))
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
