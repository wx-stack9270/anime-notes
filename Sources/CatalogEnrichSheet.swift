import SwiftUI

/// 补充番剧弹窗：搜索 Bangumi，把结果加入本地目录。
///
/// 由于 Bangumi 免费 API 无分页能力，无法一次性下载全库（实测 29598 条
/// 但 page 参数无效、搜索 limit 封顶 10 条），所以采用「搜到即补充」的方式
/// 逐步扩充目录。
struct CatalogEnrichSheet: View {
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var library: LibraryStore

    @Environment(\.dismiss) private var dismiss

    @LocalState private var keyword = ""
    @LocalState private var results: [CatalogEntry] = []
    @LocalState private var isSearching = false
    @LocalState private var hasSearched = false
    @LocalState private var status = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(alignment: .leading, spacing: LiquidGlass.Space.md) {
                searchField

                if isSearching {
                    HStack(spacing: LiquidGlass.Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("搜索中…")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LiquidGlass.Space.xl)
                } else if results.isEmpty && hasSearched {
                    emptyResult
                } else if !results.isEmpty {
                    resultList
                } else {
                    idleHint
                }
            }
            .padding(LiquidGlass.Space.lg)

            if !status.isEmpty {
                Divider()
                Text(status)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, LiquidGlass.Space.lg)
                    .padding(.bottom, LiquidGlass.Space.md)
            }

            Divider()

            HStack {
                Text("目录现有 \(catalog.totalCount) 部")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Spacer()

                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, LiquidGlass.Space.lg)
            .padding(.vertical, LiquidGlass.Space.md)
        }
        .frame(width: 580, height: 620)
    }

    // MARK: 头部

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("补充番剧目录")
                    .font(.system(size: 16, weight: .semibold))
                Text("搜索到的番剧会加入目录，之后就能按年份月份题材筛选")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, LiquidGlass.Space.lg)
        .padding(.vertical, LiquidGlass.Space.md)
    }

    // MARK: 搜索框

    private var searchField: some View {
        HStack(spacing: LiquidGlass.Space.sm) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField("输入番剧名，支持一次输入多个（逗号分隔）", text: $keyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit { Task { await runSearch() } }
            }
            .padding(.horizontal, LiquidGlass.Space.md)
            .padding(.vertical, 6)
            .background { Capsule().fill(.primary.opacity(0.06)) }

            Button("搜索") { Task { await runSearch() } }
                .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
        }
    }

    private var idleHint: some View {
        VStack(spacing: LiquidGlass.Space.sm) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text("输入番剧名开始搜索")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("小技巧：一次输入多个名字（用逗号分隔）可以批量补充")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LiquidGlass.Space.xl)
    }

    private var emptyResult: some View {
        VStack(spacing: LiquidGlass.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text("没有找到「\(keyword)」")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("试试日文名或英文名")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LiquidGlass.Space.xl)
    }

    // MARK: 结果列表

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: LiquidGlass.Space.xs) {
                ForEach(results) { entry in
                    resultRow(entry)
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func resultRow(_ entry: CatalogEntry) -> some View {
        let alreadyIn = catalog.entries.contains { $0.id == entry.id }
        let inLibrary = catalog.isInLibrary(entry, library: library.library)

        return HStack(spacing: LiquidGlass.Space.md) {
            CoverImage(urlString: entry.coverURL, width: 36, height: 51)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if !entry.airDate.isEmpty {
                        Text(entry.airDate)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    if entry.totalEpisodes > 0 {
                        Text("· \(entry.totalEpisodes) 集")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    if !entry.genres.isEmpty {
                        Text("· \(entry.genres.prefix(2).joined(separator: "/"))")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: LiquidGlass.Space.sm)

            if alreadyIn {
                Label("已在目录", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if inLibrary {
                Label("已在记录本", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.green)
            } else {
                Button {
                    let added = catalog.merge([entry])
                    catalog.link(library: library.library)
                    status = added > 0 ? "已加入《\(entry.displayTitle)》" : ""
                } label: {
                    Text("加入目录")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, LiquidGlass.Space.md)
                        .padding(.vertical, 4)
                        .glassEffect(Glass.regular, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, LiquidGlass.Space.sm)
        .padding(.vertical, 5)
        .background { RoundedRectangle(cornerRadius: LiquidGlass.Radius.xs, style: .continuous)
            .fill(.primary.opacity(0.04)) }
    }

    // MARK: 搜索逻辑

    private func runSearch() async {
        let raw = keyword.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }

        // 支持逗号分隔的批量搜索
        let terms = raw
            .components(separatedBy: CharacterSet(charactersIn: ",，、"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        isSearching = true
        hasSearched = true
        status = ""

        var collected: [CatalogEntry] = []
        var seen: Set<Int> = []

        for term in terms {
            let hits = await CatalogSync.search(term)
            for h in hits where !seen.contains(h.id) {
                seen.insert(h.id)
                collected.append(h)
            }
        }

        results = collected.sorted { $0.airDate > $1.airDate }
        isSearching = false

        if collected.isEmpty {
            status = ""
        } else if terms.count == 1 {
            status = "找到 \(collected.count) 部"
        } else {
            status = "搜索 \(terms.count) 个关键词，找到 \(collected.count) 部"
        }
    }
}