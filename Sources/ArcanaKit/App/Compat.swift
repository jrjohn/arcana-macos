//
//  Compat.swift
//  ArcanaKit — macOS shims for the handful of iOS-only SwiftUI/UIKit APIs the ported
//  presentation layer still calls (navigation bar title mode, soft-keyboard hints).
//
//  These parameter types (UIKeyboardType, NavigationBarItem.TitleDisplayMode,
//  UITextAutocapitalizationType) do not exist on macOS, so SwiftUI vends no method by
//  these names here — meaning these no-op shims add the calls back without colliding.
//  The desktop-shell phase removes the calls at the source and deletes this file.
//

#if os(macOS)
import SwiftUI
import AppKit

// Cross-platform stand-ins for the iOS system colors the ported screens used
// (rewritten from `Color(.systemGray6)` / `Color(.systemBackground)` at the source).
extension Color {
    /// iOS `.systemGray6` ≈ a subtle macOS grouped-content background.
    static var arcanaSystemGray6: Color { Color(nsColor: .underPageBackgroundColor) }
    /// iOS `.systemBackground` ≈ the macOS window background.
    static var arcanaSystemBackground: Color { Color(nsColor: .windowBackgroundColor) }
}

/// Stand-in for UIKit's `UIKeyboardType`. macOS has no soft keyboard, so the value is
/// carried for API compatibility and ignored.
public enum UIKeyboardType: Equatable, Sendable {
    case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad
    case namePhonePad, emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad
}

/// Stand-in for SwiftUI's iOS-only navigation-bar title display mode.
public enum NavigationBarTitleDisplayModeShim: Equatable, Sendable {
    case automatic, inline, large
}

/// Stand-in for UIKit's `UITextAutocapitalizationType`.
public enum TextAutocapitalizationShim: Equatable, Sendable {
    case none, words, sentences, allCharacters
}

public extension View {
    /// No-op on macOS — there is no navigation bar.
    func navigationBarTitleDisplayMode(_ mode: NavigationBarTitleDisplayModeShim) -> some View { self }

    /// No-op on macOS — there is no soft keyboard to hint.
    func keyboardType(_ type: UIKeyboardType) -> some View { self }

    /// No-op on macOS — text does not auto-capitalize on entry.
    func autocapitalization(_ style: TextAutocapitalizationShim) -> some View { self }
}
#endif
