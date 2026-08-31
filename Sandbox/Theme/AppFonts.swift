//
//  AppFonts.swift
//  Sandbox
//
//  System fonts only — the sample ships no font files.
//

import SwiftUI

enum AppFont {
    static func title(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func heading(_ size: CGFloat = 20) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func body(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .regular) }
    static func medium(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .medium) }
    static func caption(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .regular) }
}
