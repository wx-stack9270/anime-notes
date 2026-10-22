import SwiftUI

/// 「我的记录」的详情弹窗。
///
/// 与 `CatalogDetailSheet` 布局完全一致，让两处的交互体验统一（问题 4）。
/// 区别：直接编辑本地记录，不涉及目录关联。
struct RecordDetailSheet: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var catalog: CatalogStore
    let animeID: UUID
    /// 由外层 ModalOverlay 注入的关闭回调，替代 `@Environment(\.dismiss)`
    var onClose: () -> Void
    @LocalState private var showingEditor = false
    @FocusState private var notesFocused: Bool

    /// 从 store 实时取，改完立即反映
    private var anime: Anime? {
        store.library.first { $0.id == animeID }
    }

    var body: some View {
        Group {
            if let anime {
                content(anime)
            } else {
                // 记录已被删除
                VStack(spacing: 10) {
                    Text("该记录已被移除")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Button("关闭") { onClose() }
                }
                .frame(width: 540, height: 300)
            }
        }
        .sheet(isPresented: $showingEditor) {
            AnimeEditorView(store: store, existing: anime)
        }
        .sheetDismissOnBackgroundTap()
    }

    // MARK: 主体

    private func content(_ anime: Anime) -> some View {
        VStack(spacing: 0) {
            header(anime)
            glassDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: LiquidGlass.Space.lg) {
                    statusSection(anime)
                    progressSection(anime)
                    notesSection(anime)
                }
                .padding(LiquidGlass.Space.xl)
            }
            .scrollIndicators(.never)
            glassDivider()
            footerBar(anime)
        }
        .frame(width: 640, height: 620)
        .background(.regularMaterial)
        // 卡片矩形完整吃掉命中：空白处点击不穿透到 ModalOverlay 的遮罩
        .contentShape(Rectangle())
    }

    // MARK: 头部（与番剧库弹窗一致）

    /// 左封面 + 右侧纵向信息流；编辑按钮固定右上角，
    /// 题材标签与星级评分上移至此，简介占满封面右侧整幅宽度。
    private func header(_ anime: Anime) -> some View {
        HStack(alignment: .top, spacing: LiquidGlass.Space.lg) {
            FlexibleCover(urlString: anime.coverURL)
                .frame(width: 190)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: LiquidGlass.Space.sm) {
                    Text(anime.displayTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    editButton
                }

                if !anime.originalTitle.isEmpty {
                    Text(anime.originalTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    if anime.year > 0 { pill(String(anime.year), "calendar") }
                    if anime.totalEpisodes > 0 { pill("\(anime.totalEpisodes) 集", "film") }
                    pill(anime.status.displayName, anime.status.symbol)
                }

                metaRow(anime)

                if !anime.summary.isEmpty {
                    Text(anime.summary)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(LiquidGlass.Space.lg)
    }

    /// 题材标签 + 星级评分，与基本信息同一层级。评分恒显示（记录必然在库内）。
    private func metaRow(_ anime: Anime) -> some View {
        HStack(alignment: .center, spacing: LiquidGlass.Space.md) {
            if !anime.genres.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(anime.genres.prefix(4), id: \.self) { g in
                        tagChip(g)
                    }
                    if anime.genres.count > 4 {
                        Text("+\(anime.genres.count - 4)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                }
                scoreStars(anime)
        }
    }
    private func tagChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background { Capsule().fill(.primary.opacity(0.06)) }
    }

    private func scoreStars(_ anime: Anime) -> some View {
        HStack(spacing: 3) {
            ForEach(1...10, id: \.self) { v in
                Button {
                    withAnimation(LiquidGlass.Motion.quick) {
                        store.mutate(anime.id) { $0.score = ($0.score == v) ? 0 : v }
                    }
                } label: {
                    Image(systemName: v <= anime.score ? "star.fill" : "star")
                        .font(.system(size: 15))
                        .foregroundStyle(v <= anime.score ? Color.orange : Color.secondary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .help("\(v) 分（再次点击清除）")
            }
        }
        .fixedSize()
    }

    /// 纯图标按钮：不要底色、不要焦点环，只要一个铅笔图标。
    private var editButton: some View {
        Button { showingEditor = true } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help("编辑信息")
    }

    private func pill(_ text: String, _ symbol: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 11))
            Text(text).font(.system(size: 13)).monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background { Capsule().fill(.primary.opacity(0.06)) }
    }

    // MARK: 状态

    private func statusSection(_ anime: Anime) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("观看状态")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                spacing: 6
            ) {
                ForEach(WatchStatus.allCases) { status in
                    let isActive = anime.status == status
                    Button {
                        withAnimation(LiquidGlass.Motion.lift) {
                            store.mutate(anime.id) { item in
                                item.status = status
                                if status == .completed && item.totalEpisodes > 0 {
                                    item.watchedEpisodes = item.totalEpisodes
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: status.symbol)
                                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                                .symbolVariant(isActive ? .fill : .none)
                            Text(status.displayName)
                                .font(.system(size: 13, weight: isActive ? .medium : .regular))
                        }
                        .foregroundStyle(isActive ? status.tint : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: LiquidGlass.Radius.xs, style: .continuous)
                                .fill(status.tint.opacity(isActive ? 0.16 : 0.04))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 进度

    private func progressSection(_ anime: Anime) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("观看进度")

            HStack(spacing: LiquidGlass.Space.md) {
                stepper("minus", enabled: anime.watchedEpisodes > 0) {
                    store.mutate(anime.id) { $0.watchedEpisodes = max(0, $0.watchedEpisodes - 1) }
                }

                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(anime.watchedEpisodes)")
                            .font(.system(size: 22, weight: .medium))
                            .monospacedDigit()
                        Text(anime.totalEpisodes > 0 ? "/ \(anime.totalEpisodes)" : "/ ?")
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    if anime.totalEpisodes > 0 {
                        Text("\(Int(anime.progressRatio * 100))%")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)

                stepper("plus", enabled: true) {
                    store.mutate(anime.id) {
                        let cap = $0.totalEpisodes > 0 ? $0.totalEpisodes : Int.max
                        $0.watchedEpisodes = min(cap, $0.watchedEpisodes + 1)
                    }
                }
            }

            if anime.totalEpisodes > 0 {
                ProgressView(value: anime.progressRatio)
                    .progressViewStyle(.linear)
                    .tint(anime.status.tint)
                    .controlSize(.small)
            }

            HStack(spacing: 6) {
                TextField("总集数", value: Binding(
                    get: { anime.totalEpisodes },
                    set: { v in store.mutate(anime.id) { $0.totalEpisodes = max(0, v) } }
                ), format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: LiquidGlass.Radius.xs, style: .continuous)
                        .fill(.primary.opacity(0.06))
                }
                .frame(width: 76)

                if anime.totalEpisodes > 0 && anime.watchedEpisodes < anime.totalEpisodes {
                    Button {
                        withAnimation(LiquidGlass.Motion.lift) {
                            store.mutate(anime.id) {
                                $0.watchedEpisodes = $0.totalEpisodes
                                $0.status = .completed
                            }
                        }
                    } label: {
                        Text("一键看完")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background { Capsule().fill(.primary.opacity(0.07)) }
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func stepper(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .background { Circle().fill(.primary.opacity(0.07)) }
                .foregroundStyle(enabled ? .primary : .tertiary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    // MARK: 备注

    private func notesSection(_ anime: Anime) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("我的备注")
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { anime.notes },
                    set: { v in store.mutate(anime.id) { $0.notes = v } }
                ))
                .focused($notesFocused)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(height: 58)

                if anime.notes.isEmpty {
                    Text("记点什么…")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlass.Radius.sm, style: .continuous)
                    .fill(.primary.opacity(0.05))
            }
        }
    }

    // MARK: 底栏

    /// 底栏：左侧收藏、右侧「从记录中移除」，二者对称分布。
    /// 不再放「关闭」按钮——点击弹窗外的空白处即可关闭，少一个视觉噪音源。
    private func footerBar(_ anime: Anime) -> some View {
        HStack(spacing: LiquidGlass.Space.md) {
            favoriteButton(anime)
            Spacer(minLength: 0)
            removeButton(anime)
        }
        .padding(.horizontal, LiquidGlass.Space.xl)
        .padding(.vertical, LiquidGlass.Space.sm)
    }

    /// 收藏：左下角，图标放大，与右侧的移除按钮形成对称呼应。
    private func favoriteButton(_ anime: Anime) -> some View {
        Button {
            withAnimation(LiquidGlass.Motion.lift) {
                store.mutate(anime.id) { $0.isFavorite.toggle() }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: anime.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 12, weight: anime.isFavorite ? .semibold : .regular))
                    .symbolVariant(anime.isFavorite ? .fill : .none)
                Text(anime.isFavorite ? "已收藏" : "收藏")
                    .font(.system(size: 11))
            }
            .foregroundStyle(anime.isFavorite ? Color.red : Color.secondary)
            .padding(.horizontal, LiquidGlass.Space.sm)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlass.Radius.sm, style: .continuous)
                    .fill(anime.isFavorite ? Color.red.opacity(0.12) : Color.primary.opacity(0.05))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(anime.isFavorite ? "取消收藏" : "加入收藏")
    }

    /// 从记录中移除：右下角，与收藏同一视觉规格，形成左右对称。
    private func removeButton(_ anime: Anime) -> some View {
        Button {
            store.delete(anime)
            catalog.link(library: store.library)
            onClose()
        } label: {
            HStack(spacing: 6) {
                Text("从记录中移除")
                    .font(.system(size: 11))
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.red.opacity(0.9))
            .padding(.horizontal, LiquidGlass.Space.md)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlass.Radius.sm, style: .continuous)
                    .fill(Color.red.opacity(0.08))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("从我的记录本中删除这部番剧")
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
    }
}
