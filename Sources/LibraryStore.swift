import Foundation
import Combine
import SwiftUI

/// 全局唯一数据源。所有界面改动都经由此处，改完立即原子写盘。
@MainActor
final class LibraryStore: ObservableObject {

    @Published var library: [Anime] = [] {
        didSet { if loaded { persist() } }
    }

    @Published var selectedID: UUID?
    /// 默认进入番剧库（问题 2）
    @Published var filter: Filter = .catalog
    @Published var searchText: String = ""
    @Published var sortOrder: SortOrder = .updated
    @Published var layoutMode: LayoutMode = .grid
    @Published var isOnlineLookupEnabled: Bool = true

    private var loaded = false

    // MARK: - 存储位置
    // 这些路径会被 CoverCache actor 访问，因此不能受 @MainActor 隔离

    nonisolated static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("AnimeTracker", isDirectory: true)
    }

    nonisolated static var libraryFileURL: URL {
        supportDirectory.appendingPathComponent("library.json")
    }

    nonisolated static var coversDirectory: URL {
        supportDirectory.appendingPathComponent("covers", isDirectory: true)
    }

    nonisolated static var seedFileURL: URL? {
        Bundle.main.url(forResource: "seed", withExtension: "json")
    }

    // MARK: - 生命周期

    init() {
      createDirectoriesIfNeeded()
      load()
      loaded = true
      // 首次启动导入了种子片单，立刻落盘，避免下次打开又重新导入
      if FileManager.default.fileExists(atPath: Self.libraryFileURL.path) == false {
          persist()
      }
    }

    private func createDirectoriesIfNeeded() {
        for dir in [Self.supportDirectory, Self.coversDirectory] {
            if !FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - 读

    private func load() {
        let url = Self.libraryFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            // 首次启动：导入内置片单，让 App 一打开就有内容
            loadSeedIfPresent()
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            library = try decoder.decode([Anime].self, from: data)
        } catch {
            // 读取失败时不覆盖原文件，先备份再重置，避免数据丢失
            let backup = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            loadSeedIfPresent()
        }
    }

    private func loadSeedIfPresent() {
        guard let seedURL = Self.seedFileURL,
              let data = try? Data(contentsOf: seedURL),
              let seed = decodeSeed(data),
              !seed.isEmpty else { return }
        library = seed
    }

    private func decodeSeed(_ data: Data) -> [Anime]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([Anime].self, from: data)
    }

    // MARK: - 写

    private func persist() {
        let url = Self.libraryFileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(library) else { return }

        // 原子写入：先写临时文件再替换，避免中途崩溃损坏数据
        let temp = url.appendingPathExtension("tmp")
        do {
            try data.write(to: temp, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
        }
    }

    // MARK: - 增删改

    func add(_ anime: Anime) {
        library.append(anime)
        selectedID = anime.id
        touch(anime.id)
    }

    func update(_ anime: Anime) {
        guard let idx = library.firstIndex(where: { $0.id == anime.id }) else { return }
        var copy = anime
        copy.updatedAt = Date()
        library[idx] = copy
    }

    func delete(_ anime: Anime) {
        library.removeAll { $0.id == anime.id }
        if selectedID == anime.id { selectedID = nil }
    }

    func delete(at offsets: IndexSet, in subset: [Anime]) {
        let ids = offsets.compactMap { subset.indices.contains($0) ? subset[$0].id : nil }
        library.removeAll { ids.contains($0.id) }
        if let sel = selectedID, ids.contains(sel) { selectedID = nil }
    }

    /// 统一入口：应用修改并刷新时间戳
    func mutate(_ id: UUID, _ change: (inout Anime) -> Void) {
        guard let idx = library.firstIndex(where: { $0.id == id }) else { return }
        change(&library[idx])
        library[idx].updatedAt = Date()
    }

    func touch(_ id: UUID) {
        mutate(id) { $0.updatedAt = Date() }
    }

    // MARK: - 派生数据

    var selectedAnime: Anime? {
        guard let selectedID else { return nil }
        return library.first { $0.id == selectedID }
    }

    func count(for filter: Filter) -> Int {
        switch filter {
        case .all:
            return library.count
        case .favorites:
            return library.filter(\.isFavorite).count
        case .stats:
            return library.count
        case .catalog:
            // 番剧库计数由CatalogStore 提供，这里返回 0 以隐藏徽标
            return 0
        case .status(let s):
            return library.filter { $0.status == s }.count
        }
    }

    /// 当前筛选 + 搜索 + 排序后的结果
    var visibleAnime: [Anime] {
        var result: [Anime]

        switch filter {
        case .all:
            result = library
        case .favorites:
            result = library.filter(\.isFavorite)
        case .stats, .catalog:
            result = []
        case .status(let s):
            result = library.filter { $0.status == s }
        }

        let keyword = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !keyword.isEmpty {
            result = result.filter { anime in
                anime.title.lowercased().contains(keyword)
                || anime.originalTitle.lowercased().contains(keyword)
                || anime.genres.contains { $0.lowercased().contains(keyword) }
                || anime.notes.lowercased().contains(keyword)
            }
        }

        switch sortOrder {
        case .updated:  result.sort { $0.updatedAt > $1.updatedAt }
        case .added:    result.sort { $0.createdAt > $1.createdAt }
        case .title:    result.sort { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        case .score:    result.sort { ($0.score == 0 ? -1 : $0.score) > ($1.score == 0 ? -1 : $1.score) }
        case .progress: result.sort { $0.progressRatio > $1.progressRatio }
        }
        return result
    }

    // MARK: - 统计

    struct Stats {
        var total = 0
        var completed = 0
        var watching = 0
        var planToWatch = 0
        var dropped = 0
        var episodesWatched = 0
        var ratedCount = 0
        var averageScore: Double = 0
        var estimatedHours: Double = 0
        var favoriteCount = 0
        var genreCounts: [(String, Int)] = []
        var scoreHistogram: [Int: Int] = [:]
        var yearHistogram: [(Int, Int)] = []
    }

    var stats: Stats {
        var s = Stats()
        s.total = library.count
        s.completed = library.filter { $0.status == .completed }.count
        s.watching = library.filter { $0.status == .watching }.count
        s.planToWatch = library.filter { $0.status == .planToWatch }.count
        s.dropped = library.filter { $0.status == .dropped }.count
        s.episodesWatched = library.reduce(0) { $0 + $1.watchedEpisodes }
        s.estimatedHours = Double(s.episodesWatched) * 24.0 / 60.0
        s.favoriteCount = library.filter(\.isFavorite).count

        let scored = library.filter { $0.score > 0 }
        s.ratedCount = scored.count
        s.averageScore = scored.isEmpty ? 0 : Double(scored.reduce(0) { $0 + $1.score }) / Double(scored.count)

        var genreMap: [String: Int] = [:]
        for anime in library {
            for g in anime.genres where !g.isEmpty {
                genreMap[g, default: 0] += 1
            }
        }
        s.genreCounts = genreMap.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(12).map { ($0.key, $0.value) }

        var hist: [Int: Int] = [:]
        for anime in library where anime.score > 0 {
            hist[anime.score, default: 0] += 1
        }
        s.scoreHistogram = hist

        var yearMap: [Int: Int] = [:]
        for anime in library where anime.year > 0 {
            yearMap[anime.year, default: 0] += 1
        }
        s.yearHistogram = yearMap.sorted { $0.key < $1.key }.suffix(12).map { ($0.key, $0.value) }

        return s
    }

    // MARK: - 导入导出

    func exportData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(library)
    }

    struct ImportError: Error, LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// 返回成功导入的条数，或失败原因
    func importData(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let imported = try decoder.decode([Anime].self, from: data)
            // 按标题 + 集数去重，已存在的跳过
            let existing = Set(library.map { "\($0.displayTitle)|\($0.totalEpisodes)" })
            let fresh = imported.filter { !existing.contains("\($0.displayTitle)|\($0.totalEpisodes)") }
            library.append(contentsOf: fresh)
            return fresh.count
        } catch {
            throw ImportError(message: error.localizedDescription)
        }
    }

    func revealStorageFolder() {
        createDirectoriesIfNeeded()
        NSWorkspace.shared.activateFileViewerSelecting([Self.libraryFileURL])
    }
}