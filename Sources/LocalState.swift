import SwiftUI
import Combine

/// `@State` 的手写替代品。
///
/// 背景：本机 Xcode 仅安装了存根 SDK，SwiftUIMacros 插件实体缺失，
/// 使`@State` / `@Observable` 这类宏实现无法编译（普通属性包装器不受影响）。
/// 这里用 `ObservableObject` + `@Published` 自行实现等价的本地状态语义。
///
/// ⚠️ 必须用 `@StateObject` 而不是 `@ObservedObject`
/// ----------------------------------------------
/// `@ObservedObject` 不持有存储：父视图每次重渲染都会重建 Box 并把值重置回初值。
/// 实际事故：详情弹窗里点一下加减号 → `store` 变化 → 父视图重渲染 →
/// `selectedEntry` 被重置为 nil → 弹窗「点任何东西都会退出」。
/// `@StateObject` 只在视图身份首次创建时构造一次，之后跨重渲染持久，语义与 `@State` 一致。
@propertyWrapper
struct LocalState<Value>: DynamicProperty {
    final class Box: ObservableObject {
        @Published var value: Value
        init(_ value: Value) { self.value = value }
    }

    @StateObject private var box: Box

    init(wrappedValue: Value) {
        _box = StateObject(wrappedValue: Box(wrappedValue))
    }

    /// 供 `init` 中以 `_x = LocalState(wrappedValue:)` 注入初值
    init(initialValue: Value) {
        _box = StateObject(wrappedValue: Box(initialValue))
    }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    /// `$x` 投影，供 TextField 等需要 Binding 的场景
    var projectedValue: Binding<Value> {
        Binding(
            get: { box.value },
            set: { box.value = $0 }
        )
    }
}