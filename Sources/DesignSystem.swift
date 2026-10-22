import SwiftUI

/// Liquid Glass 设计令牌。
///
/// 集中定义圆角、玻璃材质层级、间距与动效参数，
/// 所有界面组件从此取用，避免样式散落各处导致的不一致。
enum LiquidGlass {

    // MARK: - 圆角

    /// 玻璃容器圆角。Liquid Glass 偏大圆角，与 macOS 26+ 系统观感一致
    enum Radius {
        /// 小元素：标签、计数浮标
        static let xs: CGFloat = 6
        /// 控件：按钮、输入框
        static let sm: CGFloat = 9
        /// 卡片：列表项、封面卡
        static let md: CGFloat = 13
        /// 面板：侧边栏、详情栏
        static let lg: CGFloat = 18
        /// 顶层容器：弹窗
        static let xl: CGFloat = 24
    }

    // MARK: - 玻璃层级
    //
    // 依据 Liquid Glass 的折射强度分三档：
    // clear 用于底层大面积留白，regular 用于常规卡片，
    // tint 用于需要强调语义的元素（如选中态）。

    /// 底层容器：侧边栏、详情栏背景
    static var clearSurface: Glass { .clear }

    /// 常规卡片：列表行、封面卡
    static var regularSurface: Glass { .regular }

    /// 强调元素：选中态、进度条
    static func tinted(_ color: Color) -> Glass {
        Glass.regular.tint(color)
    }

    // MARK: - 间距

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: - 动效
    //
    // Liquid Glass 的交互反馈靠形变传达，时长需短促（120-220ms），
    // 缓动用 easeOut，避免拖沓。

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.14)
        static let standard = Animation.easeOut(duration: 0.22)
        /// 悬浮抬起效果：缩小版 spring，模拟玻璃被拎起
        static let lift = Animation.spring(response: 0.26, dampingFraction: 0.72)
    }
}

// MARK: - 视图修饰器

extension View {

    /// 施加玻璃容器效果。
    /// - Parameters:
    ///   - glass: 玻璃层级，默认常规
    ///   - cornerRadius: 圆角，默认卡片级
    ///   - interactive: 是否响应交互（按下时产生形变反馈）
    func glassSurface(
        _ glass: SwiftUI.Glass = SwiftUI.Glass.regular,
        cornerRadius: CGFloat = LiquidGlass.Radius.md,
        interactive: Bool = false
    ) -> some View {
        self.glassEffect(glass, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .animation(interactive ? LiquidGlass.Motion.lift : LiquidGlass.Motion.standard, value: interactive)
    }

    /// 玻璃容器 + 交互悬浮抬起。
    /// 用于可点击的卡片/行。
    func glassInteractive(
        cornerRadius: CGFloat = LiquidGlass.Radius.md,
        isActive: Bool = false
    ) -> some View {
        self
            .glassEffect(
                isActive ? LiquidGlass.tinted(.accentColor) : Glass.regular,
                in: .rect(cornerRadius: cornerRadius, style: .continuous)
            )
            .scaleEffect(isActive ? 1.0 : 1.0)
            .animation(LiquidGlass.Motion.lift, value: isActive)
    }

    /// 分隔线：玻璃界面下用半透明实色比纯色更协调
    func glassDivider() -> some View {
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(height: 0.5)
    }

    /// 弹窗交互规范：只有点内容外的空白处才关闭。
    ///
    /// 问题背景：macOS 26 的 `.sheet` 默认「点击内容外即关闭」，
    /// 而 sheet 窗口通常略大于内容视图，于是内容四周那圈空隙全被判定为「外部」——
    /// 表现为「在弹窗里点任何东西都会退出」。
    ///
    /// 解法：`.presentationSizing(.fitted)` 让 sheet 贴合内容尺寸（四周不留空隙），
    /// 再用 `.presentationBackgroundInteraction(.enabled)` 明确打开「点背景关闭」——
    /// 此时命中判定只认内容本身。
    ///
    /// 另外给根视图加 `contentShape(Rectangle())`，确保整块矩形都能吃掉点击，
    /// 不会从字里行间的缝隙漏给背景。
    func sheetDismissOnBackgroundTap() -> some View {
        self
            .contentShape(Rectangle())
            .presentationSizing(.fitted)
            .presentationBackgroundInteraction(.enabled)
    }
}
