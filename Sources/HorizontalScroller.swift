import SwiftUI
import AppKit

/// 横向滚动容器：原生 NSScrollView 滚动条（细条、常显、可拖动）+ 滚轮横向滚动。
///
/// 演进史（别再走回头路）
/// --------------------
/// 1. `.scrollIndicators(.visible)` → 系统默认条又粗又占布局高度，用户不接受；
/// 2. `.scrollIndicators(.never)` → 完全看不见；
/// 3. AppKit 改 SwiftUI 内部 `NSScrollView.scrollerStyle` → **实测无效**；
/// 4. 纯 SwiftUI 自绘滚动条 → **两个硬伤**：
///    a. 拖动需要拿到内部 NSScrollView 写偏移，桥接层时好时坏，实测拖不动；
///    b. 触控板同步要监听 bounds 通知，链路同样脆弱。
///    教训：滚动条的核心是「拖动」和「同步」，自绘等于把这两件事从原生手里抢过来
///    再用脆弱的桥接还回去，得不偿失。
///
/// 最终方案：**自建 NSScrollView**，滚动条的绘制/拖动/同步全部走 AppKit 原生
/// （`scrollerStyle = .overlay` 细条 + `autohidesScrollers = false` 常显），
/// 本组件只额外做一件事——把竖直滚轮转成横向滚动。
///
/// ⚠️ 布局注意事项（上次失败的原因）
/// ------------------------------
/// - `documentView`（NSHostingView）**不要**设 `translatesAutoresizingMaskIntoConstraints`，
///   纯手动 frame 布局：宽度取 `fittingSize.width`（先 `layoutSubtreeIfNeeded`），
///   高度取内容高度；
/// - **不要**替换 `contentView`（自定义 NSClipView）——
///   在设置 documentView 之后替换会断开布局关联，内容渲染成空白。
struct HorizontalScroller<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        // 底部给滚动条留出独立空间：legacy 滚动条要占约 15pt 高，
        // 这里多给 14pt，让滚动条与年份胶囊之间有明显间距、不遮挡数字
        WheelHorizontalScroll(height: height, content: content())
            .frame(height: height + 14)
    }
}

/// 承载 NSScrollView 的 NSViewRepresentable。
/// 滚动条样式、拖动、同步全部由 NSScrollView 原生完成。
private struct WheelHorizontalScroll<Content: View>: NSViewRepresentable {
    var height: CGFloat
    let content: Content

    func makeNSView(context: Context) -> ScrollHost {
        let host = ScrollHost()
        host.setContent(content, contentHeight: height)
        return host
    }

    func updateNSView(_ nsView: ScrollHost, context: Context) {
        nsView.setContent(content, contentHeight: height)
    }

    /// NSScrollView 子类：把竖直滚轮转成横向滚动
    final class ScrollHost: NSScrollView {
        private var hosting: NSHostingView<Content>?
        private var contentHeight: CGFloat = 0

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            drawsBackground = false
            hasVerticalScroller = false
            hasHorizontalScroller = true
            // legacy 滚动条：常显、可拖，粗细固定不受系统「滚动条显示方式」影响。
            // overlay 样式在 macOS 26 上即使 autohidesScrollers=false 也会静止淡出，
            // 用户就「看不到滚轮」了，因此不用。
            scrollerStyle = .legacy
            autohidesScrollers = false
            // mini 尺寸把条压到最细（约 9pt）
            horizontalScroller?.controlSize = .mini
            verticalScrollElasticity = .none
        }

        required init?(coder: NSCoder) { fatalError() }

        func setContent(_ content: Content, contentHeight: CGFloat) {
            self.contentHeight = contentHeight
            if let host = hosting {
                host.rootView = content
            } else {
                let host = NSHostingView(rootView: content)
                // 纯手动 frame 布局，绝不走 Auto Layout（见类型注释）
                hosting = host
                documentView = host
            }
            needsLayout = true
        }

        override func layout() {
            super.layout()
            guard let host = hosting else { return }

            // ⚠️ 布局会重设 documentView 尺寸，过程中 NSClipView 会把滚动偏移
            // clamp 归零（先缩到一屏宽再放大时尤其如此）。
            // 每次界面重渲染（如点选年份胶囊）都会走一遍这里，
            // 不恢复偏移的话滚动条会跳回最左——先存后还。
            let savedX = contentView.bounds.origin.x

            // 先按当前宽度布一遍 SwiftUI 树，才能量出内容的理想宽度
            host.frame = NSRect(x: 0, y: 0,
                                width: max(bounds.width, 1),
                                height: contentHeight)
            host.layoutSubtreeIfNeeded()
            let idealW = host.fittingSize.width
            let width = idealW > 0 ? max(idealW, bounds.width) : bounds.width
            host.frame = NSRect(x: 0, y: 0, width: width, height: contentHeight)

            // 恢复滚动偏移，clamp 到合法范围
            let maxX = max(0, width - contentView.bounds.width)
            let x = min(max(savedX, 0), maxX)
            if x != contentView.bounds.origin.x {
                contentView.scroll(to: NSPoint(x: x, y: contentView.bounds.origin.y))
                reflectScrolledClipView(contentView)
            }
        }

        /// 竖直滚轮 → 横向滚动。触控板横向手势（deltaX 为主）交给系统。
        override func scrollWheel(with event: NSEvent) {
            guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else {
                super.scrollWheel(with: event)
                return
            }
            let clip = contentView
            let maxX = max(0, (documentView?.frame.width ?? 0) - clip.bounds.width)
            guard maxX > 0 else {
                super.scrollWheel(with: event)
                return
            }
            let target = min(max(clip.bounds.origin.x + event.scrollingDeltaY, 0), maxX)
            clip.scroll(to: NSPoint(x: target, y: clip.bounds.origin.y))
            reflectScrolledClipView(clip)
        }
    }
}
