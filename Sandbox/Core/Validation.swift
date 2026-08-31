//
//  Validation.swift
//  Sandbox
//

import Foundation

enum Validation {
    static func isValidEmail(_ email: String) -> Bool {
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: email)
    }

    /// The rules the backend enforces. Returned as a list so the signup screen
    /// can show which ones are still outstanding while the user types.
    static func passwordRules(_ password: String) -> [PasswordRule] {
        [
            PasswordRule(text: "At least 8 characters", satisfied: password.count >= 8),
            PasswordRule(text: "One uppercase letter", satisfied: password.range(of: "[A-Z]", options: .regularExpression) != nil),
            PasswordRule(text: "One lowercase letter", satisfied: password.range(of: "[a-z]", options: .regularExpression) != nil),
            PasswordRule(text: "One number", satisfied: password.range(of: "[0-9]", options: .regularExpression) != nil),
            PasswordRule(text: "One special character", satisfied: password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil)
        ]
    }

    static func isValidPassword(_ password: String) -> Bool {
        passwordRules(password).allSatisfy(\.satisfied)
    }
}

struct PasswordRule: Identifiable {
    let id = UUID()
    let text: String
    let satisfied: Bool
}

extension String {
    var trim: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isNotEmpty: Bool { !trim.isEmpty }
}

/// Country and dial code, defaulted from the device locale. The production app
/// ships a full picker; the sample only needs a sensible default plus a few
/// common entries.
struct CountryOption: Identifiable, Hashable {
    var id: String { code }
    let code: String
    let name: String
    let dialCode: String

    static let all: [CountryOption] = [
        .init(code: "US", name: "United States", dialCode: "+1"),
        .init(code: "CA", name: "Canada", dialCode: "+1"),
        .init(code: "GB", name: "United Kingdom", dialCode: "+44"),
        .init(code: "DE", name: "Germany", dialCode: "+49"),
        .init(code: "FR", name: "France", dialCode: "+33"),
        .init(code: "IN", name: "India", dialCode: "+91"),
        .init(code: "AU", name: "Australia", dialCode: "+61"),
        .init(code: "JP", name: "Japan", dialCode: "+81"),
        .init(code: "SG", name: "Singapore", dialCode: "+65")
    ]

    static let unitedStates = CountryOption(code: "USA", name: "United States", dialCode: "+1")

    static var current: CountryOption {
        let region = Locale.current.regionCode ?? "USA"
        return all.first { $0.code == region } ?? all[0]
    }
}
