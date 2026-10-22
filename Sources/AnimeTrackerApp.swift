import SwiftUI

@main
struct AnimeTrackerApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var catalog = CatalogStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(catalog)
                .frame(minWidth: 1000, minHeight: 620)
        }
        // 隐藏标题栏，去掉左上角「动漫记录本」文字（问题 4）。
        // hiddenTitleBar 会连标题一起隐藏，.fullSizeContent 让内容延伸到顶部。
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加番剧") {
                    NotificationCenter.default.post(name: .addAnime, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let addAnime = Notification.Name("addAnime")
}

struct ContentView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var catalog: CatalogStore
    @LocalState private var showingEditor = false
    /// 「我的记录」里点击卡片弹出的详情（问题 4：与番剧库同样的交互）
    @LocalState private var detailAnime: Anime?

    var body: some View {
        // 侧栏（176 固定） + 主区（自适应）两栏并列。
        // 不再用 VSplitView：它允许用户把分割条拖到底，导致详情面板被压扁只剩一条缝。
        HStack(spacing: 0) {
            SidebarView(store: store, catalog: catalog)

            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(width: 0.5)

            mainArea
        }
        .sheet(isPresented: $showingEditor) {
            AnimeEditorView(store: store)
        }
        // 详情弹窗走 ModalOverlay：sheet 的命中区域由系统窗口决定，
        // 内容四周空白会被误判成「点外面」，导致点任何控件都闪退。
        .overlay {
            if let anime = detailAnime {
                ModalOverlay(onDismiss: { detailAnime = nil }) {
                    RecordDetailSheet(
                        store: store, catalog: catalog, animeID: anime.id,
                        onClose: { detailAnime = nil }
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .addAnime)) { _ in
            showingEditor = true
        }
        .onAppear {
            catalog.link(library: store.library)
        }
        .onReceive(NotificationCenter.default.publisher(for: .addFromCatalog)) { note in
            guard let anime = note.userInfo?["anime"] as? Anime else { return }
            store.add(anime)
            catalog.link(library: store.library)
        }
    }

    @ViewBuilder
    private var mainArea: some View {
        // 详情统一走番剧库的点击弹窗（CatalogDetailSheet），不再常驻右侧栏
        if store.filter == .stats {
            VStack(spacing: 0) {
                topBar
                glassDivider()
                StatsView(stats: store.stats)
            }
        } else if store.filter == .catalog {
            CatalogBrowserView(catalog: catalog, library: store)
        } else {
            VStack(spacing: 0) {
                topBar
                glassDivider()
                libraryPane
            }
        }
    }

    /// 自绘工具栏：搜索、排序、视图切换
    /// （「添加番剧」按钮已按用户要求移除，仍可用菜单栏 文件→添加番剧 或 ⌘N）
    private var topBar: some View {
        HStack(spacing: LiquidGlass.Space.md) {
            // 搜索框：玻璃药丸
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField("搜索片名 / 原名 / 类型", text: searchBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
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
            .frame(maxWidth: 260)

            Spacer(minLength: 0)

            if store.filter != .stats {
                Picker("", selection: sortBinding) {
                    ForEach(SortOrder.allCases) { order in
                        Label(order.rawValue, systemImage: order.symbol).tag(order)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 98)
                .background { RoundedRectangle(cornerRadius: LiquidGlass.Radius.xs, style: .continuous).fill(.primary.opacity(0.06)) }
                .help("排序方式")

                Picker("", selection: layoutBinding) {
                    Image(systemName: "square.grid.2x2").tag(LayoutMode.grid)
                    Image(systemName: "list.bullet").tag(LayoutMode.list)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 68)
                .background { RoundedRectangle(cornerRadius: LiquidGlass.Radius.xs, style: .continuous).fill(.primary.opacity(0.06)) }
                .help("视图布局")
            }
        }
        .padding(.horizontal, LiquidGlass.Space.lg)
        .padding(.vertical, LiquidGlass.Space.sm)
        .background(.ultraThinMaterial)
    }

    private var searchBinding: Binding<String> {
        Binding(get: { store.searchText }, set: { store.searchText = $0 })
    }

    private var sortBinding: Binding<SortOrder> {
        Binding(get: { store.sortOrder }, set: { store.sortOrder = $0 })
    }

    private var layoutBinding: Binding<LayoutMode> {
        Binding(get: { store.layoutMode }, set: { store.layoutMode = $0 })
    }

    private var selectionIDBinding: Binding<UUID?> {
        Binding(get: { store.selectedID }, set: { store.selectedID = $0 })
    }

    // MARK: 列表区

    private var libraryPane: some View {
        VStack(spacing: 0) {
            let items = store.visibleAnime

            if items.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Group {
                    if store.layoutMode == .grid {
                        gridView(items)
                    } else {
                        listView(items)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: LiquidGlass.Space.md) {
            Image(systemName: store.searchText.isEmpty ? "film.stack" : "magnifyingglass")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(LiquidGlass.Space.lg)
                .background { Circle().fill(.primary.opacity(0.06)) }

            Text(store.searchText.isEmpty ? "片库还是空的" : "没有匹配「\(store.searchText)」的番剧")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Text(store.searchText.isEmpty
                 ? "点「添加番剧」录入第一部，支持联网自动补全封面与集数"
                 : "换个关键词试试，搜索会匹配片名、原名、类型与备注")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)

            if store.searchText.isEmpty {
                Button {
                    showingEditor = true
                } label: {
                    Text("添加第一部番剧")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, LiquidGlass.Space.lg)
                        .padding(.vertical, 6)
                        .glassEffect(LiquidGlass.tinted(.accentColor), in: .capsule)
                }
                .buttonStyle(.plain)
                .padding(.top, LiquidGlass.Space.xs)
            }
        }
    }

    private func gridView(_ items: [Anime]) -> some View {
        ScrollView {
            LazyVGrid(
                // 卡片宽度与番剧库保持一致（134/168），保证两页每行列数相同
                columns: [GridItem(.adaptive(minimum: 134, maximum: 168), spacing: LiquidGlass.Space.lg)],
                alignment: .leading,
                spacing: LiquidGlass.Space.xl
            ) {
                ForEach(items) { anime in
                    AnimeCardView(
                        anime: anime,
                        isSelected: false,
                        onSelect: { detailAnime = anime },
                        onBumpProgress: { bumpProgress(anime) },
                        onSetStatus: { newStatus in
                            store.mutate(anime.id) { item in
                                item.status = newStatus
                                // 标为看完时自动补齐进度
                                if newStatus == .completed && item.totalEpisodes > 0 {
                                    item.watchedEpisodes = item.totalEpisodes
                                }
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, LiquidGlass.Space.lg)
            .padding(.top, LiquidGlass.Space.lg)
            .padding(.bottom, LiquidGlass.Space.xl)
        }
    }

    private func listView(_ items: [Anime]) -> some View {
        List(selection: selectionIDBinding) {
            ForEach(items) { anime in
                AnimeRowView(
                    anime: anime,
                    isSelected: store.selectedID == anime.id,
                    onSelect: { store.selectedID = anime.id },
                    onBumpProgress: { bumpProgress(anime) },
                    onSetStatus: { newStatus in
                        store.mutate(anime.id) { item in
                            item.status = newStatus
                            if newStatus == .completed && item.totalEpisodes > 0 {
                                item.watchedEpisodes = item.totalEpisodes
                            }
                        }
                    }
                )
                .tag(anime.id)
            }
            .onDelete { offsets in
                store.delete(at: offsets, in: items)
            }
        }
        .listStyle(.inset)
    }

    /// 看过的集数 +1，播完自动标记为看完
    private func bumpProgress(_ anime: Anime) {
        store.mutate(anime.id) { item in
            let cap = item.totalEpisodes > 0 ? item.totalEpisodes : Int.max
            item.watchedEpisodes = min(cap, item.watchedEpisodes + 1)
            if item.watchedEpisodes > 0, item.status == .planToWatch {
                item.status = .watching
            }
            if item.totalEpisodes > 0 && item.watchedEpisodes >= item.totalEpisodes {
                item.status = .completed
            }
        }
    }
}
