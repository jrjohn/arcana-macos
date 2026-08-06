//
//  ShortcutTests.swift
//  ArcanaShellTests — parsing plugin menu `Shortcut` strings into SwiftUI keyboard shortcuts.
//

import Testing
import SwiftUI
@testable import ArcanaShell

@Suite("Keyboard shortcut parsing")
@MainActor
struct ShortcutTests {

    @Test("Ctrl+Shift+O → command+shift on 'o' (Windows Ctrl maps to Command)")
    func modifiers() {
        let shortcut = ShellCommands.parseShortcut("Ctrl+Shift+O")
        #expect(shortcut != nil)
        #expect(shortcut?.key.character == "o")
        #expect(shortcut?.modifiers.contains(.command) == true)
        #expect(shortcut?.modifiers.contains(.shift) == true)
    }

    @Test("a bare key defaults to the Command modifier")
    func bareKey() {
        #expect(ShellCommands.parseShortcut("N")?.modifiers.contains(.command) == true)
        #expect(ShellCommands.parseShortcut("N")?.key.character == "n")
    }

    @Test("empty input is nil")
    func empty() {
        #expect(ShellCommands.parseShortcut("") == nil)
    }
}
