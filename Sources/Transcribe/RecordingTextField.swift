import SwiftUI
import AppKit

// TextKit lays out the text once per width/content change, not on every scroll pass.
struct RecordingTextField: NSViewRepresentable {
    let title: String
    @Binding var text: String
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> RecordingNSTextView {
        let view = RecordingNSTextView()
        view.delegate = context.coordinator
        view.setContent(text)
        return view
    }

    func updateNSView(_ view: RecordingNSTextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = isEnabled
        view.setAccessibilityLabel(title)
        view.setContent(text)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RecordingNSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: nsView.measuredHeight(width: width))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RecordingTextField
        init(parent: RecordingTextField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? RecordingNSTextView else { return }
            view.invalidateMeasurement()
            parent.text = view.string
        }
    }
}

final class RecordingNSTextView: NSTextView {
    private var measuredWidth: CGFloat?
    private var cachedHeight: CGFloat = 24

    convenience init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layout.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
        drawsBackground = false
        textContainerInset = .zero
        container.lineFragmentPadding = 0
        font = .systemFont(ofSize: 16)
        textColor = .textColor
        isAutomaticTextReplacementEnabled = false
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        defaultParagraphStyle = paragraph
        typingAttributes = [.font: NSFont.systemFont(ofSize: 16), .paragraphStyle: paragraph, .foregroundColor: NSColor.textColor]
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    func setContent(_ text: String) {
        guard string != text else { return }
        string = text
        undoManager?.removeAllActions()
        invalidateMeasurement()
    }

    func invalidateMeasurement() {
        measuredWidth = nil
        invalidateIntrinsicContentSize()
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        if measuredWidth == width { return cachedHeight }
        guard let layoutManager, let textContainer else { return 24 }
        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        cachedHeight = max(24, ceil(max(layoutManager.usedRect(for: textContainer).maxY, layoutManager.extraLineFragmentRect.maxY)))
        measuredWidth = width
        return cachedHeight
    }
}
