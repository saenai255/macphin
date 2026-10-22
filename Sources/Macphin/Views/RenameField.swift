import AppKit
import SwiftUI

struct InlineRename: View {
    let item: FileItem
    let pane: PaneState
    let window: WindowState
    var centered = false

    var body: some View {
        RenameField(name: item.name, selectsWholeName: item.opensAsFolder, centered: centered) { newName in
            pane.renamingURL = nil
            if let newName { Actions(window: window, pane: pane).commitRename(item.url, to: newName) }
        }
    }
}

private struct RenameField: NSViewRepresentable {
    let name: String
    let selectsWholeName: Bool
    let centered: Bool
    let onFinish: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeNSView(context: Context) -> AutoFocusTextField {
        let field = AutoFocusTextField(string: name)
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.alignment = centered ? .center : .natural
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.focusRingType = .exterior
        field.selectionLength = selectsWholeName ? name.utf16.count : (name as NSString).deletingPathExtension.utf16.count
        return field
    }

    func updateNSView(_ field: AutoFocusTextField, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    final class AutoFocusTextField: NSTextField {
        var selectionLength = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, window.makeFirstResponder(self) else { return }
                self.currentEditor()?.selectedRange = NSRange(location: 0, length: self.selectionLength)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onFinish: (String?) -> Void
        private var finished = false

        init(onFinish: @escaping (String?) -> Void) { self.onFinish = onFinish }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.cancelOperation(_:)):
                finish(nil)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                finish(control.stringValue)
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            finish(field.stringValue)
        }

        private func finish(_ value: String?) {
            guard !finished else { return }
            finished = true
            DispatchQueue.main.async { self.onFinish(value) }
        }
    }
}
