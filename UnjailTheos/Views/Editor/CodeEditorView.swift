import SwiftUI
import UIKit

/// 基于 UITextView 的代码编辑器，支持语法高亮
/// 可替换为 Runestone 以获得更完整的编辑体验
struct CodeEditorView: UIViewRepresentable {
    @Binding var text: String
    let language: SyntaxLanguage
    var onSave: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.backgroundColor = UIColor.systemBackground
        textView.isEditable = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.keyboardDismissMode = .interactive

        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        toolbar.items = [
            UIBarButtonItem(title: "保存", style: .done, target: context.coordinator, action: #selector(Coordinator.save))
        ]
        toolbar.sizeToFit()
        textView.inputAccessoryView = toolbar

        applyHighlight(to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
            applyHighlight(to: textView)
        }
        context.coordinator.parent = self
    }

    private func applyHighlight(to textView: UITextView) {
        let selected = textView.selectedRange
        textView.attributedText = SyntaxHighlighter.highlight(text, language: language)
        textView.selectedRange = selected
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeEditorView

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            let selected = textView.selectedRange
            textView.attributedText = SyntaxHighlighter.highlight(textView.text, language: parent.language)
            textView.selectedRange = selected
        }

        @objc func save() {
            parent.onSave?()
        }
    }
}
