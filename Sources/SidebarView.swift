import SwiftUI

// MARK: - 侧边栏

/// 侧边栏。固定 176pt 宽，采用 Liquid Glass 底板 + 悬浮式选中项。
struct SidebarView: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var catalog: CatalogStore
    @LocalState private var showingImporter = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: LiquidGlass.Space.xl) {
                    // 番剧库是默认页，放最顶
                    group("浏览") {
                        row(.catalog)
                    }

                    // 我的观看状态筛选（.all 已移除，见问题 2）
                    group("我的记录") {
                        ForEach(WatchStatus.allCases) { status in
                            row(.status(status))
                        }
                        row(.favorites)
                    }

                    group("其他") {
                        row(.stats)
                    }

                    group("数据") {
                        actionButton("导入片库", "square.and.arrow.down") {
                            showingImporter = true
                        }
                        actionButton("存储位置", "folder") {
                            store.revealStorageFolder()
                        }
                    }
                }
                .padding(.horizontal, LiquidGlass.Space.sm)
                .padding(.top, LiquidGlass.Space.md)
                .padding(.bottom, LiquidGlass.Space.lg)
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)
        }
        .frame(width: 176)
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(width: 0.5)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { outcome in
            switch outcome {
            case .failure:
                return
            case .success(let urls):
                guard let url = urls.first else { return }
                let needsScope = url.startAccessingSecurityScopedResource()
                defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return }
                _ = try? store.importData(data)
            }
        }
    }

    // MARK: 分组

    @ViewBuilder
    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, LiquidGlass.Space.sm)
                .padding(.bottom, 4)

            content()
        }
    }

    // MARK: 导航项

    private func row(_ filter: Filter) -> some View {
        let isActive = store.filter == filter

        return Button {
            withAnimation(LiquidGlass.Motion.standard) {
                store.filter = filter
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: filter.symbol)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .frame(width: 18)
                    .symbolVariant(isActive ? .fill : .none)

                Text(filter.label)
                    .font(.system(size: 14, weight: isActive ? .medium : .regular))
                    .lineLimit(1)

                Spacer(minLength: 2)

                if filter != .stats {
                    let value = filter == .catalog
                        ? catalog.totalCount
                        : store.count(for: filter)
                    Text(countText(value))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(isActive ? .primary : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            // 计数用半透明胶囊，不套玻璃——此处密度过高会导致整层不渲染
                            Capsule().fill(.primary.opacity(isActive ? 0.08 : 0.05))
                        }
                }
            }
            .foregroundStyle(isActive ? tint(for: filter) : Color.primary.opacity(0.75))
            .padding(.horizontal, LiquidGlass.Space.md)
            .padding(.vertical, 8)
            // 选中态用半透明底色，不能用 glassEffect：
            // 玻璃在浅色材质上会折射成近乎不透明的色块，把文字完全盖住
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: LiquidGlass.Radius.xs, style: .continuous)
                        .fill(tint(for: filter).opacity(0.16))
                }
            }
            .overlay {
                if isActive {
                    // 左侧一条状态色指示条，比整块底色更克制
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint(for: filter))
                        .frame(width: 3.5)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(filter.label)
    }

    // MARK: 操作按钮

    private func actionButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.primary.opacity(0.6))
            .padding(.horizontal, LiquidGlass.Space.md)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 计数显示：超过 9999 用「万」缩写（3万 / 2.9万），避免 29,600 之类的长数字
    /// 在固定宽度的侧边栏里被折成两行
    private func countText(_ value: Int) -> String {
        guard value >= 10000 else { return "\(value)" }
        let w = Double(value) / 10000
        let text = w >= 10 ? String(format: "%.0f", w) : String(format: "%.1f", w)
        // 去掉无意义的 .0（3.0万 → 3万）
        let trimmed = text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        return "\(trimmed)万"
    }

    private func tint(for filter: Filter) -> Color {
        if case .status(let s) = filter { return s.tint }
        return .accentColor
    }
}
