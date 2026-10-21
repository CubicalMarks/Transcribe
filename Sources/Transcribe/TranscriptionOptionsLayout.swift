import SwiftUI

// Keep one instance of each control. ViewThatFits builds both full sets of
// pickers while testing candidates, including every language menu item.
struct TranscriptionOptionsLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let horizontalWidth = sizes.reduce(0) { $0 + $1.width } + 16
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? horizontalWidth
        let height = horizontalWidth <= width
            ? sizes.map(\.height).max() ?? 0
            : sizes.reduce(0) { $0 + $1.height } + 10
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let horizontal = sizes.reduce(0) { $0 + $1.width } + 16 <= bounds.width
        var point = bounds.origin
        for (index, view) in subviews.enumerated() {
            let size = sizes[index]
            let y = horizontal ? bounds.midY - size.height / 2 : point.y
            view.place(at: CGPoint(x: point.x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            if horizontal { point.x += size.width + 16 }
            else { point.y += size.height + 10 }
        }
    }
}
