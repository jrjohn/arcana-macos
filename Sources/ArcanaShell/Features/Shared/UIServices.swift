//
//  UIServices.swift
//  ArcanaShell — cross-cutting UI services: confirm/error dialogs, transient toasts, and a
//  CSV document type for file export. Injected through the environment and rendered by the
//  `.shellUIServices(...)` modifier on the shell.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Dialogs

@MainActor
@Observable
public final class DialogService {
    public struct Confirmation: Identifiable {
        public let id = UUID()
        let title: String
        let message: String
        let confirmTitle: String
        let isDestructive: Bool
        let action: () -> Void
    }

    public var confirmation: Confirmation?
    public var errorMessage: String?

    public init() {}

    /// Presents a confirm/cancel dialog; `action` runs on confirm.
    public func confirm(_ title: String, message: String, confirmTitle: String = "OK",
                        destructive: Bool = false, action: @escaping () -> Void) {
        confirmation = Confirmation(title: title, message: message, confirmTitle: confirmTitle,
                                    isDestructive: destructive, action: action)
    }

    public func showError(_ message: String) { errorMessage = message }
}

// MARK: - Toasts

@MainActor
@Observable
public final class ToastCenter {
    public struct Toast: Identifiable, Equatable {
        public let id = UUID()
        let text: String
        let systemImage: String
    }

    public private(set) var current: Toast?

    public init() {}

    /// Shows a transient toast that auto-dismisses.
    public func show(_ text: String, systemImage: String = "checkmark.circle.fill") {
        let toast = Toast(text: text, systemImage: systemImage)
        current = toast
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.current?.id == toast.id { self?.current = nil }
        }
    }
}

// MARK: - Rendering modifier

public extension View {
    /// Renders the shell's dialogs (error alert + confirm dialog) and the toast overlay.
    func shellUIServices(_ dialogs: DialogService, _ toasts: ToastCenter) -> some View {
        self
            .alert("Error", isPresented: Binding(
                get: { dialogs.errorMessage != nil },
                set: { if !$0 { dialogs.errorMessage = nil } })) {
                Button("OK", role: .cancel) { dialogs.errorMessage = nil }
            } message: {
                Text(dialogs.errorMessage ?? "")
            }
            .confirmationDialog(
                dialogs.confirmation?.title ?? "",
                isPresented: Binding(
                    get: { dialogs.confirmation != nil },
                    set: { if !$0 { dialogs.confirmation = nil } }),
                titleVisibility: .visible,
                presenting: dialogs.confirmation) { confirmation in
                    Button(confirmation.confirmTitle, role: confirmation.isDestructive ? .destructive : nil) {
                        confirmation.action()
                        dialogs.confirmation = nil
                    }
                    Button("Cancel", role: .cancel) { dialogs.confirmation = nil }
                } message: { confirmation in
                    Text(confirmation.message)
                }
            .overlay(alignment: .bottom) {
                if let toast = toasts.current {
                    Label(toast.text, systemImage: toast.systemImage)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.separator))
                        .shadow(radius: 8, y: 2)
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: toasts.current)
    }
}

// MARK: - CSV document (for .fileExporter)

public struct CSVDocument: FileDocument {
    public static let readableContentTypes: [UTType] = [.commaSeparatedText, .plainText]
    public var text: String

    public init(_ text: String) { self.text = text }

    public init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
