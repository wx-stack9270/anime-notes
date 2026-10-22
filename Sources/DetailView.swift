import SwiftUI

/// 右侧详情面板。固定 290pt 宽，纵向分区滚动。
/// 信息按「身份 → 状态 → 进度 → 评分 → 简介 → 备注」优先级自上而下排列，
/// 保证在窄栏内也能一眼看到最重要的信息。
struct DetailView: View {
    @ObservedObject var store: LibraryStore
    let anime: Anime

    @LocalState private var isEditing = false
    @FocusState private var notesFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidGlass.Space.lg) {
                header
                statusPicker
                progressSection
                scoreSection
                metaSection
                genresSection
                summarySection
                notesSection
                dangerSection
            }
            .padding(LiquidGlass.Space.lg)
        }
        .scrollIndicators(.never)
        .background {
            ZStack {
                // 底衬用 Material 而非 glassEffect：内容区大量玻璃嵌套时
                // 逐层折射会导致顶部区域渲染中断
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [.clear, .primary.opacity(0.03)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .sheet(isPresented: $isEditing) {
            AnimeEditorView(store: store, existing: anime)
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidGlass.Space.md) {
            // 封面 + 标题并排：封面 96 宽，给文字留足空间
            HStack(alignment: .top, spacing: LiquidGlass.Space.md) {
                FlexibleCover(urlString: anime.coverURL)
                    .frame(width: 96)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: LiquidGlass.Space.xs) {
                    Text(anime.displayTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !anime.originalTitle.isEmpty && anime.originalTitle != anime.displayTitle {
                        Text(anime.originalTitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    // 年份 + 集数：玻璃药丸
                    HStack(spacing: LiquidGlass.Space.xs) {
                        if anime.year > 0 {
                            infoPill(String(anime.year), "calendar")
                        }
                        if anime.totalEpisodes > 0 {
                            infoPill("\(anime.totalEpisodes) 集", "film")
                        }
                    }
                    .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 操作行：收藏 + 编辑 + 估算时长
            HStack(spacing: LiquidGlass.Space.sm) {
                iconButton(
                    anime.isFavorite ? "heart.fill" : "heart",
                    tint: anime.isFavorite ? .red : .secondary,
                    help: anime.isFavorite ? "取消收藏" : "收藏"
                ) {
                    withAnimation(LiquidGlass.Motion.lift) {
                        store.mutate(anime.id) { $0.isFavorite.toggle() }
                    }
                }

                Button {
                    isEditing = true
                } label: {
                    Label("编辑信息", systemImage: "square.and.pencil")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, LiquidGlass.Space.md)
                        .padding(.vertical, 5)
                        .glassEffect(Glass.regular, in: .capsule)
                }
                .buttonStyle(.plain)
                .help("编辑番剧信息")

                Spacer(minLength: 0)

                if anime.watchedEpisodes > 0 {
                    Label(anime.estimatedHoursText, systemImage: "clock")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func infoPill(_ text: String, _ symbol: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 12))
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background { Capsule().fill(.primary.opacity(0.06)) }
    }

    private func iconButton(_ symbol: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 28, height: 26)
                .glassEffect(Glass.regular, in: .rect(cornerRadius: LiquidGlass.Radius.xs, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: 状态

    private var statusPicker: some View {
        VStack(alignment: .leading, spacing: LiquidGlass.Space.sm) {
            sectionLabel("观看状态")

            // 四宫格按钮组：比 segmented 在窄栏里更易点，且能显示中文全称
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: LiquidGlass.Space.xs),
                          GridItem(.flexible(), spacing: LiquidGlass.Space.xs)],
                spacing: LiquidGlass.Space.xs
            ) {
                ForEach(WatchStatus.allCases) { status in
                    statusButton(status)
                }
            }
        }
    }

    private func statusButton(_ status: WatchStatus) -> some View {
        let isActive = anime.status == status
        return Button {
            withAnimation(LiquidGlass.Motion.lift) {
                store.mutate(anime.id) { item in
                    item.status = status
                    if status == .completed && item.totalEpisodes > 0 {
                        item.watchedEpisodes = item.totalEpisodes
                    }
                }
            }
        } label: {
            // 玻璃必须作为独立底层视图，不能直接修饰内容
            // ——直接 glassEffect 会把包裹的子树一起吞掉，文字会消失
            HStack(spacing: 4) {
                Image(systemName: status.symbol)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .symbolVariant(isActive ? .fill : .none)
                Text(status.displayName)
                    .font(.system(size: 13, weight: isActive ? .medium : .regular))
            }
            .foregroundStyle(isActive ? status.tint : .secondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .glassEffect(
                LiquidGlass.tinted(status.tint),
                in: .rect(cornerRadius: LiquidGlass.Radius.xs, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 进度

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: LiquidGlass.Space.md) {
            sectionLabel("观看进度")

            // 大号数字 + 步进按钮
            HStack(spacing: LiquidGlass.Space.md) {
                stepperButton("minus", enabled: anime.watchedEpisodes > 0) {
                    store.mutate(anime.id) { $0.watchedEpisodes = max(0, $0.watchedEpisodes - 1) }
                }

                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(anime.watchedEpisodes)")
                            .font(.system(size: 30, weight: .medium))
                            .monospacedDigit()
                        Text(anime.totalEpisodes > 0 ? "/ \(anime.totalEpisodes)" : "/ ?")
                            .font(.system(size: 14))
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

                stepperButton("plus", enabled: true) {
                    store.mutate(anime.id) {
                        let cap = $0.totalEpisodes > 0 ? $0.totalEpisodes : Int.max
                        $0.watchedEpisodes = min(cap, $0.watchedEpisodes + 1)
                    }
                }
            }

            if anime.totalEpisodes > 0 {
                VStack(spacing: LiquidGlass.Space.xs) {
                    ProgressView(value: anime.progressRatio)
                        .progressViewStyle(.linear)
                        .tint(anime.status.tint)
                        .scaleEffect(y: 1.6)
                        .clipShape(Capsule())

                    HStack {
                        Text("\(anime.watchedEpisodes) / \(anime.totalEpisodes) 集")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(anime.estimatedHoursText)
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // 总集数 + 一键看完
            HStack(spacing: LiquidGlass.Space.sm) {
                TextField("总集数", value: Binding(
                    get: { anime.totalEpisodes },
                    set: { newValue in store.mutate(anime.id) { $0.totalEpisodes = max(0, newValue) } }
                ), format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .padding(.vertical, 5)
                .background { RoundedRectangle(cornerRadius: LiquidGlass.Radius.xs, style: .continuous).fill(.primary.opacity(0.06)) }
                .frame(width: 74)

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
                            .padding(.horizontal, LiquidGlass.Space.md)
                            .padding(.vertical, 5)
                            .glassEffect(Glass.regular, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func stepperButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? .primary : .tertiary)
                .frame(width: 32, height: 32)
                .glassEffect(Glass.regular, in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    // MARK: 评分

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: LiquidGlass.Space.sm) {
            HStack {
                sectionLabel("我的评分")
                Spacer()
                if anime.score > 0 {
                    Button {
                        store.mutate(anime.id) { $0.score = 0 }
                    } label: {
                        Text("清除")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 2) {
                ForEach(1...10, id: \.self) { value in
                    Button {
                        withAnimation(LiquidGlass.Motion.quick) {
                            store.mutate(anime.id) { item in
                                item.score = (item.score == value) ? 0 : value
                            }
                        }
                    } label: {
                        Image(systemName: value <= anime.score ? "star.fill" : "star")
                            .font(.system(size: 15))
                            .foregroundStyle(value <= anime.score ? Color.orange : Color.secondary.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .help("\(value) 分")
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 记录时间

    private var metaSection: some View {
        HStack(spacing: LiquidGlass.Space.md) {
            metaItem("calendar", "添加于", anime.createdAt.formatted(.dateTime.month(.abbreviated).day()))
            metaItem("clock.arrow.circlepath", "更新", anime.updatedAt.formatted(.dateTime.month(.abbreviated).day()))
            Spacer(minLength: 0)
        }
    }

    private func metaItem(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text("\(label) \(value)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: 类型

    @ViewBuilder
    private var genresSection: some View {
        if !anime.genres.isEmpty {
            VStack(alignment: .leading, spacing: LiquidGlass.Space.sm) {
                sectionLabel("类型")
                FlowLayout(spacing: LiquidGlass.Space.xs) {
                    ForEach(anime.genres, id: \.self) { genre in
                        Text(genre)
                            .font(.system(size: 12))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background { Capsule().fill(.primary.opacity(0.06)) }
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: 简介

    @ViewBuilder
    private var summarySection: some View {
        if !anime.summary.isEmpty {
            VStack(alignment: .leading, spacing: LiquidGlass.Space.sm) {
                sectionLabel("简介")
                Text(anime.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 备注

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: LiquidGlass.Space.sm) {
            sectionLabel("我的备注")
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { anime.notes },
                    set: { newValue in store.mutate(anime.id) { $0.notes = newValue } }
                ))
                .focused($notesFocused)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(height: 66)

                if anime.notes.isEmpty {
                    Text("记点什么…")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }
            .padding(LiquidGlass.Space.sm)
            .background { RoundedRectangle(cornerRadius: LiquidGlass.Radius.sm, style: .continuous).fill(.primary.opacity(0.05)) }
        }
    }

    // MARK: 删除

    private var dangerSection: some View {
        VStack(spacing: 0) {
            glassDivider()
            Button {
                store.delete(anime)
            } label: {
                Label("从记录本移除", systemImage: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, LiquidGlass.Space.sm)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
    }
}
