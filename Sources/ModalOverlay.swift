import SwiftUI

/// 覆盖式弹窗容器：只有点击内容**外**的遮罩才关闭。
///
/// 为什么不用 `.sheet`
/// ------------------
/// macOS 26 的 `.sheet` 默认「点击内容外即关闭」。sheet 窗口由系统决定尺寸，
/// 通常略大于内容视图，四周那圈空白被系统判定为「内容外」——
/// 表现就是「在弹窗里点任何东西都退出」。
/// `.presentationSizing(.fitted)` + `.presentationBackgroundInteraction(.enabled)`
/// 实测仍会误判：命中区域由系统窗口决定，SwiftUI 约束不住。
///
/// 层级设计（本文件的核心）
/// ----------------------
/// 遮罩不是与内容平级的兄弟视图，而是内容的 **`.background`**：
///
///     content()                      ← 上层：卡片本体
///       └─ .background { 遮罩 }       ← 下层：铺满全窗口
///
/// SwiftUI 的命中测试里 background 恒定低于宿主视图，
/// 因此落在卡片矩形内的点击**不可能**冒泡到遮罩；
/// 落在卡片之外的点击则命中铺满全窗口的遮罩 → 关闭。
///
/// 这样就不必依赖手势优先级，也就不会出现
/// 「点进度条加减号却把弹窗点关」的仲裁事故。
///
/// ⚠️ 反面教材：不要用 `ZStack { Button(遮罩); content() }`
/// 平级时 Button 虽走控件命中优先级，但在 macOS 上仍偶发被上层控件抢走事件，
/// 实测导致点状态按钮闪退。平级 + `.background` 才稳定。
struct ModalOverlay<Content: View>: View {
    /// 点击遮罩时回调（关闭弹窗）
    var onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            // 让内容在满屏容器里居中，同时不改变内容自身尺寸
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // ⚠️ 这里绝不能加 contentShape(Rectangle())：
            // 容器铺满全窗口，加了之后整个窗口都算内容的命中区域，
            // 遮罩（background）将收不到任何点击，「点空白关闭」会彻底失效。
            // 卡片自身的命中范围由 ModalCard 内部的 contentShape 负责。
            .background {
                Rectangle()
                    .fill(.black.opacity(0.32))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
            }
            // Esc 仍然可以关闭
            .onExitCommand(perform: onDismiss)
    }
}

/// 弹窗卡片标准外包装：明确整块矩形吃掉命中，
/// 卡片内空白处的点击不会穿透到底下 ModalOverlay 的遮罩。
struct ModalCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .contentShape(Rectangle())
    }
}
