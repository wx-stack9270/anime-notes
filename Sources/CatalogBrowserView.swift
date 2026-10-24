import SwiftUI

/// 番剧库浏览页。
/// 左侧年份/月份/题材筛选，右侧番剧卡片网格，右键或按钮一键标记为看过。
struct CatalogBrowserView: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var library: LibraryStore

    @LocalState private var searchText = ""
    @LocalState private var isEnriching = false
    @LocalState private var enrichStatus = ""
    @LocalState private var showEnrichSheet = false
    @LocalState private var selectedEntry: CatalogEntry?
    @LocalState private var toast: String?

    private let coverWidth: CGFloat = 134

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5)
            content
        }
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showEnrichSheet) {
            CatalogEnrichSheet(catalog: catalog, library: library)
                .sheetDismissOnBackgroundTap()
        }
        // 详情弹窗走 ModalOverlay 而非 sheet：
        // sheet 的命中区域由系统窗口决定，内容四周的空白会被误判成「点外面」，
        // 导致在弹窗内点击任何控件都闪退。详见 ModalOverlay 的注释。
        .overlay {
            if let entry = selectedEntry {
                ModalOverlay(onDismiss: { selectedEntry = nil }) {
                    CatalogDetailSheet(
                        entry: entry, catalog: catalog, library: library,
                        onClose: { selectedEntry = nil }
                    )
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, LiquidGlass.Space.lg)
                    .padding(.vertical, 8)
                    .glassEffect(Glass.regular, in: .capsule)
                    .padding(.bottom, LiquidGlass.Space.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(LiquidGlass.Motion.standard, value: toast)
    }

    // MARK: - 筛选栏

    private var filterBar: some View {
        // 整体左对齐：年份、月份、题材共用同一条起始竖线，不随内容宽度漂移
        VStack(alignment: .leading, spacing: LiquidGlass.Space.sm) {
            HStack(spacing: LiquidGlass.Space.sm) {
                // 搜索
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("搜索番剧名", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, LiquidGlass.Space.md)
                .padding(.vertical, 5)
                .background { Capsule().fill(.primary.opacity(0.06)) }
                .frame(width: 190)

                // 未看过 + 题材：同一栏，纯图标 toggle，无文字
                unwatchedToggle
                genreMenu

                Spacer(minLength: 0)

                // 补充目录
                Button {
                    showEnrichSheet = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("搜索番剧并加入目录")

                // 结果计数
                Text("\(filtered.count)")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            // 年份独占一行
            yearPicker

            // 月份独占一行（纯数字）
            monthStrip
        }
        .padding(.horizontal, LiquidGlass.Space.lg)
        .padding(.vertical, LiquidGlass.Space.md)
    }

    /// 「只看没看过」图标开关。纯图标无文字，点击直接切换。
    private var unwatchedToggle: some View {
        let isOn = catalog.filter.unwatchedOnly
        return Button {
            withAnimation(LiquidGlass.Motion.standard) {
                catalog.filter.unwatchedOnly.toggle()
            }
        } label: {
            // 无斜杆 = 显示全部；带斜杆 = 只看没看过
            Image(systemName: isOn ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 24, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: LiquidGlass.Radius.xs, style: .continuous)
                        .fill(isOn ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "当前：只看没看过（点击改为显示全部）" : "当前：显示全部（点击只看没看过）")
    }


    /// 年份筛选：单行横向滚动。
    ///
    /// 年份从 1960s 排到今年有 60+ 个，平铺会占掉五行把卡片区挤没，
    /// 因此做成单行横向滚动。滚动条是自己画的细条（见 `HorizontalScroller`），
    /// 系统滚动条在 macOS 上又粗又长且初始位置会算错，都不可用。
    private var yearPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("年份")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            HorizontalScroller(height: 26) {
                HStack(spacing: 4) {
                    allYearsChip
                    ForEach(availableYearList, id: \.self) { y in
                        yearChip(year: y)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    /// 「全部」：清除年份与月份筛选。固定在最左，符合「从宽到窄」的筛选直觉。
    private var allYearsChip: some View {
        let isActive = catalog.filter.year == nil
        return Button {
            withAnimation(LiquidGlass.Motion.standard) {
                catalog.filter.year = nil
                catalog.filter.month = nil
            }
        } label: {
            Text("全部")
                .font(.system(size: 13, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background {
                    Capsule()
                        .fill(isActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("不限年份")
    }

    /// 有数据的年份，倒序
    private var availableYearList: [Int] {
        catalog.availableYears
    }

    /// 年份胶囊。再点一次已选中的年份即取消年份筛选（不再需要「全部」按钮）。
    private func yearChip(year: Int) -> some View {
        let isActive = catalog.filter.year == year
        return Button {
            withAnimation(LiquidGlass.Motion.standard) {
                if isActive {
                    // 再次点击已选年份 → 清除年份筛选
                    catalog.filter.year = nil
                } else {
                    catalog.filter.year = year
                    // 换年份时清掉月份与题材，避免筛出空集
                    catalog.filter.month = nil
                    catalog.filter.genre = nil
                }
            }
        } label: {
            Text(String(year))
                .font(.system(size: 13, weight: isActive ? .medium : .regular))
                .monospacedDigit()
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    // 用半透明底色而非 glassEffect：玻璃在浅底上会变成不透明色块
                    Capsule()
                        .fill(isActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 月份筛选：直接显示数字，胶囊按钮，选中高亮。
    /// 不再用柱状图——柱高随数据波动导致视觉噪声大，且用户明确要求只看数字。
    private var monthStrip: some View {
        let counts = catalog.monthCounts(year: catalog.filter.year)
        return VStack(alignment: .leading, spacing: 4) {
            Text("月份")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            if counts.isEmpty {
                Text("该年份暂无月份数据")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 4) {
                    ForEach(counts, id: \.month) { item in
                        monthChip(month: item.month, count: item.count)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 月份胶囊：只显示数字，不显示该月番剧数量。
    /// 数量信息噪音大且会诱导用户「按数量挑月份」，筛选只需关心月份本身。
    private func monthChip(month: Int, count: Int) -> some View {
        let isActive = catalog.filter.month == month
        return Button {
            catalog.filter.month = isActive ? nil : month
        } label: {
            Text("\(month)")
                .font(.system(size: 13, weight: isActive ? .medium : .regular))
                .monospacedDigit()
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: LiquidGlass.Radius.xs, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(month) 月 · \(count) 部")
    }

    private func monthLabel(_ m: Int) -> String {
        let names = ["", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12"]
        guard m >= 1, m <= 12 else { return "?" }
        return names[m]
    }

    private var genreMenu: some View {
        let counts = catalog.genreCounts(year: catalog.filter.year).prefix(14)
        return Menu {
            Button("清除题材筛选") { catalog.filter.genre = nil }
            Divider()
            ForEach(Array(counts), id: \.genre) { item in
                Button {
                    catalog.filter.genre = catalog.filter.genre == item.genre ? nil : item.genre
                } label: {
                    if catalog.filter.genre == item.genre {
                        Label("\(item.genre) (\(item.count))", systemImage: "checkmark")
                    } else {
                        Text("\(item.genre) (\(item.count))")
                    }
                }
            }
        } label: {
            // 纯图标无文字，且不显示菜单下拉箭头
            let isOn = catalog.filter.genre != nil
            Image(systemName: isOn ? "tag.fill" : "tag")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 24, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: LiquidGlass.Radius.xs, style: .continuous)
                        .fill(isOn ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                }
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        if catalog.totalCount == 0 {
            CatalogEmptyState(onEnrich: { showEnrichSheet = true })
        } else if filtered.isEmpty {
            VStack(spacing: LiquidGlass.Space.md) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("没有符合条件的番剧")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                Button("清除筛选") {
                    catalog.filter.clear()
                    searchText = ""
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: coverWidth, maximum: 168), spacing: LiquidGlass.Space.lg)],
                    alignment: .leading,
                    spacing: LiquidGlass.Space.xl
                ) {
                    ForEach(filtered) { entry in
                        CatalogCardView(
                            entry: entry,
                            isWatched: catalog.isWatched(entry),
                            onOpen: { selectedEntry = entry },
                            onMarkWatched: { markWatched(entry) }
                        )
                    }
                }
                .padding(.horizontal, LiquidGlass.Space.lg)
                .padding(.vertical, LiquidGlass.Space.lg)
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: - 数据

    /// 应用搜索后的结果
    private var filtered: [CatalogEntry] {
        let base = catalog.results
        let kw = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !kw.isEmpty else { return base }
        return base.filter { e in
            e.displayTitle.lowercased().contains(kw)
                || e.originalTitle.lowercased().contains(kw)
                || e.genres.contains { $0.lowercased().contains(kw) }
        }
    }

    // MARK: - 操作

    /// 标记为看过：写入记录本并给出反馈
    private func markWatched(_ entry: CatalogEntry) {
        // 已在记录本里则不重复添加（按规范化标题判断，忽略集数差异）
        if catalog.isInLibrary(entry, library: library.library) {
            flash("《\(entry.displayTitle)》已在你的记录本里")
            return
        }

        // 标记为看过：进度自动补满，评分交给用户在详情面板里给
        library.add(entry.makeRecord(status: .completed))
        catalog.link(library: library.library)
        flash("已标记《\(entry.displayTitle)》为看过")
    }

    private func flash(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == message { toast = nil }
        }
    }
}

// MARK: - 番剧卡片

struct CatalogCardView: View {
    let entry: CatalogEntry
    let isWatched: Bool
    let onOpen: () -> Void
    let onMarkWatched: () -> Void

    @LocalState private var isHovering = false

    private let coverWidth: CGFloat = 134
    private var coverHeight: CGFloat { coverWidth * 1.42 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                CoverImage(urlString: entry.coverURL, width: coverWidth, height: coverHeight)

                // 已看标记：玻璃胶囊
                if isWatched {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                        Text("已看")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background { Capsule().fill(.black.opacity(0.55)) }
                    .padding(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(5)
                }

                // 悬浮时的快捷标记按钮
                if isHovering && !isWatched {
                    Button(action: onMarkWatched) {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("看过")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background { Capsule().fill(Color.accentColor) }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(5)
                }
            }
            .frame(width: coverWidth, height: coverHeight)
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlass.Radius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LiquidGlass.Radius.sm, style: .continuous)
                    .strokeBorder(.white.opacity(isHovering ? 0.4 : 0), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isHovering ? 0.16 : 0.06),
                    radius: isHovering ? 10 : 4, y: isHovering ? 4 : 2)
            .scaleEffect(isHovering ? 1.02 : 1.0)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(entry.airDate.isEmpty ? "日期未知" : entry.airDate)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                    if entry.totalEpisodes > 0 {
                        Text("· \(entry.totalEpisodes) 集")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }

                if entry.rating > 0 || !entry.airStatusText.isEmpty {
                    HStack(spacing: 4) {
                        if entry.rating > 0 {
                            Label(String(format: "%.1f", entry.rating), systemImage: "star.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.orange)
                        }
                        if !entry.airStatusText.isEmpty {
                            Text(entry.airStatusText)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background { Capsule().fill(.primary.opacity(0.06)) }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: coverWidth, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovering = $0 }
        .animation(LiquidGlass.Motion.lift, value: isHovering)
        .contextMenu {
            Button("标记为看过", systemImage: "checkmark.circle") { onMarkWatched() }
            Button("加入想看", systemImage: "bookmark") { addToLibrary(.planToWatch) }
            Divider()
            Button("查看详情", systemImage: "info.circle") { onOpen() }
        }
    }

    private func addToLibrary(_ status: WatchStatus) {
        let record = entry.makeRecord(status: status)
        NotificationCenter.default.post(
            name: .addFromCatalog, object: nil,
            userInfo: ["anime": record]
        )
    }
}

// MARK: - 空状态

struct CatalogEmptyState: View {
    let onEnrich: () -> Void

    var body: some View {
        VStack(spacing: LiquidGlass.Space.lg) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)

            Text("番剧库是空的")
                .font(.system(size: 17, weight: .medium))

            Text("搜索番剧名加入目录，之后就能按年份、月份、题材\n筛选浏览，并把看过的标记进记录本")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 320)

            Button(action: onEnrich) {
                Text("搜索番剧")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, LiquidGlass.Space.xl)
                    .padding(.vertical, 7)
                    .glassEffect(LiquidGlass.tinted(.accentColor), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 目录条目详情

/// 番剧详情弹窗。整合了原右侧详情栏的全部编辑能力（状态 / 进度 / 评分 / 备注），
/// 取代常驻右侧栏（见问题 1）。
struct CatalogDetailSheet: View {
    let entry: CatalogEntry
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var library: LibraryStore
    /// 由外层 ModalOverlay 注入的关闭回调。
    /// 不用 `@Environment(\.dismiss)`：本视图已改为 overlay 呈现，
    /// dismiss 环境值在 overlay 场景下不可靠。
    var onClose: () -> Void

    @LocalState private var showingEditor = false
    @FocusState private var notesFocused: Bool

    /// 拉取到的完整详情（评分/星期/放送状态），未拉取时为 nil。
    /// 打开弹窗时按需异步拉取，不阻塞现有字段展示。
    @LocalState private var detail: CatalogSync.Detail?
    @LocalState private var detailLoaded = false

    /// 记录本里对应的本地记录（已标记过时存在）
    private var record: Anime? {
        library.library.first {
            $0.displayTitle == entry.displayTitle && $0.totalEpisodes == entry.totalEpisodes
        }
    }

    /// 放送星期：优先用拉取到的详情，其次用目录已有值
    private var weekdayText: String {
        if let d = detail, d.airWeekday > 0 {
            let names = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
            return names[d.airWeekday]
        }
        return entry.weekdayText
    }

    /// 放送状态：优先用拉取到的详情，其次用目录已有值
    private var airStatusText: String {
        if let d = detail {
            switch d.airStatus {
            case 1: return "在播"
            case 2: return "已完结"
            case 3: return "未定档"
            default: break
            }
        }
        return entry.airStatusText
    }

    /// Bangumi 均分：优先详情，其次目录
    private var communityRating: Double {
        if let d = detail, d.rating > 0 { return d.rating }
        return entry.rating
    }

    private var communityRatingCount: Int {
        if let d = detail, d.ratingCount > 0 { return d.ratingCount }
        return entry.ratingCount
    }

    private var isInLibrary: Bool { record != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            glassDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: LiquidGlass.Space.lg) {
                    statusSection
                    progressSection
                    if isInLibrary { notesSection }
                }
                .padding(LiquidGlass.Space.xl)
            }
            .scrollIndicators(.never)
            glassDivider()
            footerBar
        }
        .frame(width: 640, height: 620)
        .background(.regularMaterial)
        // 卡片矩形完整吃掉命中：空白处点击不穿透到 ModalOverlay 的遮罩
        .contentShape(Rectangle())
        .sheet(isPresented: $showingEditor) {
            AnimeEditorView(store: library, existing: record)
        }
        .task {
            await loadDetail()
        }
    }

    /// 拉取 Bangumi 详情补充评分/星期/放送状态。已有数据时不重复请求。
    private func loadDetail() async {
        guard !detailLoaded, entry.id > 0 else { return }
        detailLoaded = true
        // 优先用目录里已有的值，缺失时才联网补齐
        if entry.rating > 0, entry.airStatus > 0 { return }
        guard let d = await CatalogSync.fetchDetail(subjectID: entry.id) else { return }
        detail = d
        // 回写目录，让评分/放送信息持久化，下次无需重新联网
        catalog.enrich(entryID: entry.id, detail: d)
    }

    // MARK: 头部

    /// 头部：左封面 + 右侧「标题 → 副标题 → 基本信息 → 标签/评分 → 简介」纵向信息流。
    ///
    /// 关键调整（对照设计稿）：
    /// - 编辑按钮独立固定在头部右上角，不再挤在标题信息流里；
    /// - 题材标签与星级评分上移到头部，和发布日期、集数同一层级，一眼看完；
    /// - 简介改为占满封面右侧整幅宽度，不再塞进 150pt 的窄条里被截断。
    private var header: some View {
        HStack(alignment: .top, spacing: LiquidGlass.Space.lg) {
            FlexibleCover(urlString: entry.coverURL)
                .frame(width: 190)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: LiquidGlass.Space.sm) {
                    Text(entry.displayTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    editButton
                }

                if !entry.originalTitle.isEmpty {
                    Text(entry.originalTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    if !entry.airDate.isEmpty { pill(entry.airDate, "calendar") }
                    if entry.totalEpisodes > 0 { pill("\(entry.totalEpisodes) 集", "film") }
                    if !weekdayText.isEmpty { pill(weekdayText, "calendar.badge.clock") }
                    if !airStatusText.isEmpty { pill(airStatusText, "circle.inset.filled") }
                    if isInLibrary { pill("已记录", "checkmark.circle") }
                }

                metaRow

                if !entry.summary.isEmpty {
                    Text(entry.summary)
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

    /// 题材标签 + 社区评分 + 我的评分。
    /// 标签占据剩余宽度，评分固定在右侧同一行。
    @ViewBuilder
    private var metaRow: some View {
        if !entry.genres.isEmpty || communityRating > 0 || isInLibrary {
            HStack(alignment: .center, spacing: LiquidGlass.Space.md) {
                if !entry.genres.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(entry.genres.prefix(4), id: \.self) { g in
                            tagChip(g)
                        }
                        if entry.genres.count > 4 {
                            Text("+\(entry.genres.count - 4)")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if communityRating > 0 {
                    communityRatingBadge
                }
                if isInLibrary { scoreStars }
            }
        }
    }

    /// Bangumi 社区评分：橙色星 + 均分 + 人数
    private var communityRatingBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.orange)
            Text(String(format: "%.1f", communityRating))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
            if communityRatingCount > 0 {
                Text("(\(communityRatingCount))")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .help("Bangumi 用户均分")
    }

    private func tagChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background { Capsule().fill(.primary.opacity(0.06)) }
    }

    /// 星级评分：未加入记录本时置灰，只作信息展示。
    private var scoreStars: some View {
        let current = record?.score ?? 0
        return HStack(spacing: 3) {
            ForEach(1...10, id: \.self) { v in
                Button {
                    guard let rec = record else { return }
                    withAnimation(LiquidGlass.Motion.quick) {
                        library.mutate(rec.id) { $0.score = ($0.score == v) ? 0 : v }
                    }
                } label: {
                    Image(systemName: v <= current ? "star.fill" : "star")
                        .font(.system(size: 15))
                        .foregroundStyle(v <= current ? Color.orange : Color.secondary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(record == nil)
                .help(record == nil ? "加入记录本后可评分" : "\(v) 分（再次点击清除）")
            }
        }
        .fixedSize()
    }

    /// 纯图标按钮：不要底色、不要焦点环，只要一个铅笔图标。
    /// 头部已有标题和标签提供视觉重量，编辑入口属于次级操作。
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

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("观看状态")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                spacing: 6
            ) {
                ForEach(WatchStatus.allCases) { status in
                    statusButton(status)
                }
            }
        }
    }

    private func statusButton(_ status: WatchStatus) -> some View {
        // 已在记录本里则修改本地记录，否则新建一条
        let isActive = isInLibrary ? (record?.status == status) : false
        return Button {
            withAnimation(LiquidGlass.Motion.lift) {
                apply(status: status)
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

    private func apply(status: WatchStatus) {
        if let rec = record {
            library.mutate(rec.id) { item in
                item.status = status
                if status == .completed && item.totalEpisodes > 0 {
                    item.watchedEpisodes = item.totalEpisodes
                }
            }
        } else {
            library.add(entry.makeRecord(status: status))
        }
        catalog.link(library: library.library)
    }

    // MARK: 进度

    @ViewBuilder
    private var progressSection: some View {
        if isInLibrary, let rec = record {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("观看进度")

                HStack(spacing: LiquidGlass.Space.md) {
                    stepper("minus", enabled: rec.watchedEpisodes > 0) {
                        library.mutate(rec.id) { $0.watchedEpisodes = max(0, $0.watchedEpisodes - 1) }
                    }

                    VStack(spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(rec.watchedEpisodes)")
                                .font(.system(size: 22, weight: .medium))
                                .monospacedDigit()
                            Text(rec.totalEpisodes > 0 ? "/ \(rec.totalEpisodes)" : "/ ?")
                                .font(.system(size: 13))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        if rec.totalEpisodes > 0 {
                            Text("\(Int(rec.progressRatio * 100))%")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    stepper("plus", enabled: true) {
                        library.mutate(rec.id) {
                            let cap = $0.totalEpisodes > 0 ? $0.totalEpisodes : Int.max
                            $0.watchedEpisodes = min(cap, $0.watchedEpisodes + 1)
                        }
                    }
                }

                if rec.totalEpisodes > 0 {
                    ProgressView(value: rec.progressRatio)
                        .progressViewStyle(.linear)
                        .tint(rec.status.tint)
                        .scaleEffect(y: 1.5)
                        .clipShape(Capsule())
                }

                HStack(spacing: 6) {
                    TextField("总集数", value: Binding(
                        get: { rec.totalEpisodes },
                        set: { v in library.mutate(rec.id) { $0.totalEpisodes = max(0, v) } }
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

                    if rec.totalEpisodes > 0 && rec.watchedEpisodes < rec.totalEpisodes {
                        Button {
                            withAnimation(LiquidGlass.Motion.lift) {
                                library.mutate(rec.id) {
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
        } else {
            // 未记录时给出快捷加入
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("观看状态")
                Text("选一个状态即可加入我的记录")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
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

    @ViewBuilder
    private var notesSection: some View {
        if let rec = record {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("我的备注")
                ZStack(alignment: .topLeading) {
                    TextEditor(text: Binding(
                        get: { rec.notes },
                        set: { v in library.mutate(rec.id) { $0.notes = v } }
                    ))
                    .focused($notesFocused)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .frame(height: 58)

                    if rec.notes.isEmpty {
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
    }

    // MARK: 底栏

    /// 底栏：右下角「从记录中移除」，左侧留空与「我的记录」详情弹窗的收藏按钮对称。
    /// 不再放「关闭」按钮——点击弹窗外的空白处即可关闭。
    private var footerBar: some View {
        HStack(spacing: LiquidGlass.Space.md) {
            Spacer(minLength: 0)
            if isInLibrary {
                Button {
                    if let rec = record { library.delete(rec) }
                    catalog.link(library: library.library)
                    onClose()
                } label: {
                    HStack(spacing: 6) {
                        Text("从记录中移除")
                            .font(.system(size: 11))
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(.horizontal, LiquidGlass.Space.sm)
                    .padding(.vertical, 4)
                    .background {
                        RoundedRectangle(cornerRadius: LiquidGlass.Radius.sm, style: .continuous)
                            .fill(Color.red.opacity(0.08))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("从我的记录本中删除这部番剧")
            }
        }
        .padding(.horizontal, LiquidGlass.Space.xl)
        .padding(.vertical, LiquidGlass.Space.sm)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

extension Notification.Name {
    static let addFromCatalog = Notification.Name("addFromCatalog")
}