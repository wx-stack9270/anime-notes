import Foundation
import SwiftUI

/// 番剧目录条目：来自 Bangumi 的公开番剧库，字段比本地记录更精简。
struct CatalogEntry: Identifiable, Codable, Hashable {
    /// Bangumi subject id，全库唯一
    var id: Int
    var title: String
    var originalTitle: String
    var coverURL: String
    var summary: String

    /// 放送日期 YYYY-MM-DD，年份与月份筛选依赖此字段
    var airDate: String
    var totalEpisodes: Int

    /// 题材标签
    var genres: [String]
    /// 热度（收藏数），用于「热门」排序
    var rank: Int

    var year: Int {
        Int(airDate.prefix(4)) ?? 0
    }

    /// 1-12，无日期时为 0
    var month: Int {
        // 注意：不能用 airDate[5..<7] 这种整数下标，Swift 6 已废弃，
        // 且会连带引发下游的解析错误。改用 String.Index 定位。
        guard airDate.count >= 7 else { return 0 }
        let start = airDate.index(airDate.startIndex, offsetBy: 5)
        let end = airDate.index(start, offsetBy: 2)
        return Int(airDate[start..<end]) ?? 0
    }

    var displayTitle: String {
        title.isEmpty ? originalTitle : title
    }

    var progressText: String {
        totalEpisodes > 0 ? "\(totalEpisodes) 集" : "集数未知"
    }

    /// 转成本地记录
    func makeRecord(status: WatchStatus) -> Anime {
        var a = Anime()
        a.title = displayTitle
        a.originalTitle = originalTitle
        a.summary = summary
        a.coverURL = coverURL
        a.totalEpisodes = totalEpisodes
        a.genres = genres
        a.year = year
        a.status = status
        if status == .completed { a.watchedEpisodes = totalEpisodes }
        return a
    }
}

/// 目录元信息
struct CatalogMeta: Codable {
    /// 用户主动补充过的时间
    var lastEnrichedAt: Date?
}

// MARK: - 筛选条件

/// 番剧库筛选器。年份/月份/题材可组合。
struct CatalogFilter: Equatable {
    var year: Int?
    var month: Int?
    var genre: String?
    /// 只看未看过的
    var unwatchedOnly = false

    var isActive: Bool {
        return year != nil || month != nil || genre != nil || unwatchedOnly
    }

    mutating func clear() {
        year = nil
        month = nil
        genre = nil
        unwatchedOnly = false
    }
}

// MARK: - 番剧目录仓库

/// 番剧目录的持久化与筛选。
/// 与 `LibraryStore`（我的记录）职责分离：目录是「可浏览的全库」，记录是「我看过什么」。
@MainActor
final class CatalogStore: ObservableObject {

    @Published private(set) var entries: [CatalogEntry] = []
    @Published private(set) var meta = CatalogMeta()
    @Published var filter = CatalogFilter() {
        didSet { rebuildIndex() }
    }
    @Published private(set) var searching = false

    /// 记录本里已有的番剧 id 集合，用于「未看过」筛选与已看标记
    private var watchedIDs: Set<Int> = []
    /// title+集数 → id，用于把本地记录关联回目录条目
    private var libraryKeys: [String: Int] = [:]

    // 索引：按年份分桶，桶内存的是 CatalogEntry.id（绝不用下标做键，
    // 下标会随entries 重排失效，越界会导致 SIGTRAP 崩溃）
    private var byYear: [Int: [Int]] = [:]
    private var knownIDs: Set<Int> = []

    /// 落盘结构
    private struct Payload: Codable {
        var entries: [CatalogEntry]
        var meta: CatalogMeta
    }

    private static var catalogURL: URL {
        LibraryStore.supportDirectory.appendingPathComponent("catalog.json")
    }

    init() {
        loadUserCatalog()
        if entries.isEmpty { loadBundledCatalog() }
        buildIndexes()
    }

    // MARK: - 持久化

    /// 优先读用户扩充过的目录（存于 Application Support）
    private func loadUserCatalog() {
        try? FileManager.default.createDirectory(
            at: LibraryStore.supportDirectory, withIntermediateDirectories: true)
        load(from: Self.catalogURL)
    }

    /// 读取打包内置的精选目录
    private func loadBundledCatalog() {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        decodeEntries(from: data)
    }

    private func load(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        decodeEntries(from: data)
    }

    private func decodeEntries(from data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 兼容两种格式：裸数组 / 带 meta 的包装
        if let payload = try? decoder.decode(Payload.self, from: data) {
            entries = payload.entries
            meta = payload.meta
        } else if let list = try? decoder.decode([CatalogEntry].self, from: data) {
            entries = list
        }
    }

    private func save() {
        let payload = Payload(entries: entries, meta: meta)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: Self.catalogURL, options: .atomic)
    }

    // MARK: - 索引

    private func buildIndexes() {
        byYear.removeAll(keepingCapacity: true)
        knownIDs.removeAll(keepingCapacity: true)
        knownIDs.reserveCapacity(entries.count)
        for e in entries {
            knownIDs.insert(e.id)
            if e.year > 0 { byYear[e.year, default: []].append(e.id) }
        }
    }

    private func rebuildIndex() {
        // filter 变化时无需重建索引，只重算结果集
        objectWillChange.send()
    }

    /// 把本地记录关联到目录条目
    func link(library: [Anime]) {
        watchedIDs.removeAll(keepingCapacity: true)
        libraryKeys.removeAll(keepingCapacity: true)

        // 先记下记录本里的所有「标题+集数」键，值为 0 表示尚未在目录中匹配到
        var wanted: Set<String> = []
        wanted.reserveCapacity(library.count)
        for anime in library {
            let key = Self.normalizedTitle(anime.displayTitle)
            libraryKeys[key] = 0
            wanted.insert(key)
        }

        // 再扫描目录，把命中的条目标记为已看。
        // 注意：同一作品可能有多个条目（TV 版 / 剧场版 / 不同季），
        // 它们共用同一个规范化键，因此全部都要加入 watchedIDs。
        for e in entries {
            let key = Self.normalizedTitle(e.displayTitle)
            if wanted.contains(key) {
                watchedIDs.insert(e.id)
                // libraryKeys 只记首个命中的 id，避免后续条目覆盖
                if libraryKeys[key] == 0 { libraryKeys[key] = e.id }
            }
        }
    }

    /// 规范化标题：去掉季数/剧场版等后缀与括注，用于跨表匹配。
    /// 公开给视图层做「是否已在记录本」的判断。
    static func normalizedTitle(_ title: String) -> String {
        return linkKey(title, 0)
    }

    /// 记录本中是否已有该条目（按规范化标题匹配，不比较集数）
    func isInLibrary(_ entry: CatalogEntry, library: [Anime]) -> Bool {
        let key = Self.normalizedTitle(entry.displayTitle)
        return library.contains { Self.normalizedTitle($0.displayTitle) == key }
    }

    /// 建立关联键。同一作品在目录与记录本里的集数可能不同（如剧场版 1 集 vs TV 版 24 集），
    /// 因此只用「清理过的标题」做键，不带集数。
    private static func linkKey(_ title: String, _ episodes: Int) -> String {
        var t = title
        // 去掉「xxx 第二季」「xxx 剧场版」等后缀差异
        for suffix in ["第二季", "第一季", "第三季", "剧场版", " TV版", " OVA", " SP"] {
            if t.hasSuffix(suffix) {
                t = String(t.dropLast(suffix.count))
                    .trimmingCharacters(in: .whitespaces)
                break
            }
        }
        // 去掉「（数字）」「第N季」等括注
        while let open = t.firstIndex(of: "（"), let close = t[open...].firstIndex(of: "）") {
            t = String(t[t.startIndex..<open]) + String(t[t.index(after: close)...])
        }
        t = t.trimmingCharacters(in: .whitespaces)
        // 去掉标点差异：「孤独摇滚！」vs「孤独摇滚」、「Re：零」vs「Re:零」
        let punctuation = CharacterSet(charactersIn: "！!·・. 　:：-—_～~")
        return t.components(separatedBy: punctuation)
            .joined()
            .trimmingCharacters(in: .whitespaces)
    }

    func isWatched(_ entry: CatalogEntry) -> Bool {
        watchedIDs.contains(entry.id)
    }

    // MARK: - 筛选结果

    /// 库里可用的年份（降序）
    var availableYears: [Int] {
        Set(entries.map(\.year)).filter { $0 > 0 }.sorted(by: >)
    }

    /// 指定年份（或全部）下的月份计数
    func monthCounts(year: Int?) -> [(month: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for e in entries {
            if let year, e.year != year { continue }
            if e.month > 0 { counts[e.month, default: 0] += 1 }
        }
        return counts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// 题材列表与计数
    func genreCounts(year: Int?) -> [(genre: String, count: Int)] {
        var counts: [String: Int] = [:]
        for e in entries {
            if let year, e.year != year { continue }
            for g in e.genres {
                counts[g, default: 0] += 1
            }
        }
        let sorted: [(genre: String, count: Int)] = counts
            .map { (genre: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.genre < rhs.genre }
                return lhs.count > rhs.count
            }
        return sorted
    }

    /// 按当前筛选条件返回结果
    var results: [CatalogEntry] {
        // 注意：pool 里存的是 CatalogEntry.id，不是数组下标。
        // 早期版本误用 byID.keys（是 id）当下标访问 entries，导致越界崩溃。
        var pool: [Int]
        if let y = filter.year, let ids = byYear[y] {
            pool = ids
        } else {
            pool = entries.map(\.id)
        }

        let wantMonth: Int? = filter.month
        let wantGenre: String? = filter.genre
        let hideWatched: Bool = filter.unwatchedOnly
        let watched: Set<Int> = watchedIDs

        // id → 条目，避免用下标做二次索引
        var byEntryID: [Int: CatalogEntry] = [:]
        byEntryID.reserveCapacity(entries.count)
        for e in entries {
            byEntryID[e.id] = e
        }

        var out: [CatalogEntry] = []
        out.reserveCapacity(pool.count)

        for id in pool {
            // 防御：id 缺失时跳过，绝不越界
            guard let e = byEntryID[id] else { continue }
            if let m = wantMonth, e.month != m { continue }
            if let g = wantGenre, !e.genres.contains(g) { continue }
            if hideWatched && watched.contains(e.id) { continue }
            out.append(e)
        }

        // 默认按放送日期新→旧
        out.sort { $0.airDate > $1.airDate }
        return out
    }

    var totalCount: Int { entries.count }

    // MARK: - 写入

    /// 合并新搜索到的条目，按 id 去重
    @discardableResult
    func merge(_ incoming: [CatalogEntry]) -> Int {
        var added = 0
        var known = knownIDs

        for e in incoming {
            guard !e.title.isEmpty || !e.originalTitle.isEmpty else { continue }
            if known.contains(e.id) { continue }
            known.insert(e.id)
            entries.append(e)
            added += 1
        }

        if added > 0 {
            buildIndexes()
            meta.lastEnrichedAt = Date()
            save()
        }
        return added
    }

    /// 记录本里的番剧是否已在目录中；不在则加入（用于手动添加的老记录）
    func ensureInCatalog(_ anime: Anime) {
        let key = Self.normalizedTitle(anime.displayTitle)
        // 值 0 表示记录本里有但目录里还没这条，负数同理，都不算已关联
        guard let id = libraryKeys[key], id > 0 else { return }
        watchedIDs.insert(id)
    }
}