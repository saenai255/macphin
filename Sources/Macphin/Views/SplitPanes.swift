import AppKit
import SwiftUI

struct SplitPanes: View {
    let tab: TabState
    let window: WindowState

    private let minimumWidth: CGFloat = 220

    var body: some View {
        GeometryReader { geometry in
            let total = geometry.size.width
            if tab.isSplit {
                let first = clampedWidth(total * tab.splitFraction, total: total)
                HStack(spacing: 0) {
                    pane(0).frame(width: first)
                    SplitDivider { location in
                        tab.splitFraction = clampedWidth(location, total: total) / max(total, 1)
                    }
                    pane(1).frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: "split")
            } else {
                pane(0)
            }
        }
    }

    private func pane(_ index: Int) -> some View {
        PaneView(pane: tab.panes[index], window: window, isActive: index == tab.activePaneIndex)
    }

    private func clampedWidth(_ width: CGFloat, total: CGFloat) -> CGFloat {
        guard total > minimumWidth * 2 else { return total / 2 }
        return min(max(width, minimumWidth), total - minimumWidth)
    }
}

private struct SplitDivider: View {
    let onDrag: (CGFloat) -> Void

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(coordinateSpace: .named("split")).onChanged { onDrag($0.location.x) })
    }
}
