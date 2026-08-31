//
//  AppColors.swift
//  Sandbox
//
//  A self-contained dark palette. Nothing here is tied to a brand asset
//  catalog — swap the hex values and the whole app follows.
//

import SwiftUI

enum AppColors {
    // Brand
    static let primary        = Color(hex: 0x6C5CE7)   // indigo
    static let primaryPressed = Color(hex: 0x5646D4)
    static let primarySoft    = Color(hex: 0x6C5CE7).opacity(0.16)
    static let accent         = Color(hex: 0x00D2A8)   // teal

    // Surfaces
    static let background     = Color(hex: 0x0E1016)
    static let surface        = Color(hex: 0x171A22)
    static let surfaceRaised  = Color(hex: 0x1F2430)
    static let border         = Color(hex: 0x2A303C)

    // Text
    static let textPrimary    = Color(hex: 0xF2F4F8)
    static let textSecondary  = Color(hex: 0x9AA3B2)
    static let textDisabled   = Color(hex: 0x5A6273)

    // Status
    static let success        = Color(hex: 0x2ECC71)
    static let warning        = Color(hex: 0xF5A623)
    static let error          = Color(hex: 0xFF5A5F)
    static let offline        = Color(hex: 0x6B7280)

    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x151A2B), background],
                       startPoint: .top,
                       endPoint: .bottom)
    }

    static var primaryGradient: LinearGradient {
        LinearGradient(colors: [primary, Color(hex: 0x8B7BFF)],
                       startPoint: .leading,
                       endPoint: .trailing)
    }
}

extension Color {
    /// `Color(hex: 0x6C5CE7)` — compile-time checked, unlike the string form.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}
