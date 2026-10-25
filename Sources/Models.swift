import Foundation
import SwiftUI

// MARK: - 观看状态

enum WatchStatus: String, CaseIterable, Codable, Identifiable, Hashable {
    // rawValue 是存储值（英文，稳定不变），displayName 是界面显示文案（中文，可随时调整）
    case watching    = "watching"
    case planToWatch = "planToWatch"
    case completed   = "completed"
    case dropped     = "dropped"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .watching:    return "在看"
        case .planToWatch: return "想看"
        case .completed:   return "看完"
        case .dropped:     return "弃番"
        }
    }

    var symbol: String {
        switch self {
        case .watching:    return "play.circle.fill"
        case .planToWatch: return "bookmark.fill"
        case .completed:   return "checkmark.circle.fill"
        case .dropped:     return "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .watching:    return Color(red: 0.16, green: 0.53, blue: 0.95)
        case .planToWatch: return Color(red: 0.94, green: 0.62, blue: 0.09)
        case .completed:   return Color(red: 0.15, green: 0.64, blue: 0.33)
        case .dropped:     return Color(red: 0.72, green: 0.24, blue: 0.24)
        }
    }
}

// MARK: - 番剧记录

struct Anime: Identifiable, Codable, Hashable {
    var id: UUID = UUID()

    /// 关联的 Bangumi subject id，0 表示未关联。
    /// 用于从本地记录反查 Bangumi 详情（评分、放送信息等）。
    var bangumiID: Int = 0

    var title: String = ""
    /// 日文原名
    var originalTitle: String = ""
    var summary: String = ""
    var coverURL: String = ""

    /// 总集数，0 表示未知
    var totalEpisodes: Int = 0
    /// 已看集数
    var watchedEpisodes: Int = 0

    var status: WatchStatus = .planToWatch
    /// 0 表示未评分，否则 1...10
    var score: Int = 0

    var genres: [String] = []
    var notes: String = ""
    var isFavorite: Bool = false

    /// 放送年份，用于统计
    var year: Int = 0

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // 自定义解码：所有字段用 decodeIfPresent，缺键时回落到默认值。
    // 合成 Codable 对「有默认值的非可选字段」仍要求键必须存在，
    // 旧版本数据缺少新增字段（如 bangumiID）会导致整库解码失败、被误判损坏。
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bangumiID     = try c.decodeIfPresent(Int.self, forKey: .bangumiID) ?? 0
        title         = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        originalTitle = try c.decodeIfPresent(String.self, forKey: .originalTitle) ?? ""
        summary       = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        coverURL      = try c.decodeIfPresent(String.self, forKey: .coverURL) ?? ""
        totalEpisodes = try c.decodeIfPresent(Int.self, forKey: .totalEpisodes) ?? 0
        watchedEpisodes = try c.decodeIfPresent(Int.self, forKey: .watchedEpisodes) ?? 0
        status        = try c.decodeIfPresent(WatchStatus.self, forKey: .status) ?? .planToWatch
        score         = try c.decodeIfPresent(Int.self, forKey: .score) ?? 0
        genres        = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
        notes         = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isFavorite    = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        year          = try c.decodeIfPresent(Int.self, forKey: .year) ?? 0
        createdAt     = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt     = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    init(title: String = "", originalTitle: String = "", summary: String = "",
         coverURL: String = "", totalEpisodes: Int = 0, watchedEpisodes: Int = 0,
         status: WatchStatus = .planToWatch, score: Int = 0, genres: [String] = [],
         notes: String = "", isFavorite: Bool = false, year: Int = 0) {
        self.title = title
        self.originalTitle = originalTitle
        self.summary = summary
        self.coverURL = coverURL
        self.totalEpisodes = totalEpisodes
        self.watchedEpisodes = watchedEpisodes
        self.status = status
        self.score = score
        self.genres = genres
        self.notes = notes
        self.isFavorite = isFavorite
        self.year = year
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespaces).isEmpty ? originalTitle : title
    }

    var progressRatio: Double {
        guard totalEpisodes > 0 else { return watchedEpisodes > 0 ? 1 : 0 }
        return min(1.0, Double(watchedEpisodes) / Double(totalEpisodes))
    }

    var progressText: String {
        if totalEpisodes > 0 {
            return "\(watchedEpisodes) / \(totalEpisodes)"
        }
        return watchedEpisodes > 0 ? "已看 \(watchedEpisodes) 集" : "—"
    }

    /// 粗略估算观看时长（分钟），按每集 24 分钟计
    var estimatedMinutes: Int {
        watchedEpisodes * 24
    }

    var estimatedHoursText: String {
        let hours = Double(estimatedMinutes) / 60.0
        return String(format: "%.1f 小时", hours)
    }
}

// MARK: - 排序方式

enum SortOrder: String, CaseIterable, Identifiable {
    case updated   = "最近更新"
    case added     = "最近添加"
    case title     = "标题"
    case score     = "评分"
    case progress  = "进度"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .updated:  return "clock"
        case .added:    return "sparkles"
        case .title:    return "textformat"
        case .score:    return "star"
        case .progress: return "chart.bar"
        }
    }
}

// MARK: - 布局模式

enum LayoutMode: String, CaseIterable {
    case grid
    case list
}

// MARK: - 侧边栏筛选项

enum Filter: Hashable, Identifiable {
    case all
    case status(WatchStatus)
    case favorites
    case catalog
    case stats

    var id: String {
        switch self {
        case .all:        return "all"
        case .favorites:  return "favorites"
        case .catalog:    return "catalog"
        case .stats:      return "stats"
        case .status(let s): return "status-\(s.rawValue)"
        }
    }

    var label: String {
        switch self {
        case .all:            return "我的记录"
        case .favorites:      return "收藏"
        case .catalog:        return "番剧库"
        case .stats:          return "统计"
        case .status(let s):  return s.displayName
        }
    }

    var symbol: String {
        switch self {
        case .all:            return "square.grid.2x2"
        case .favorites:      return "heart.fill"
        case .catalog:        return "books.vertical.fill"
        case .stats:          return "chart.bar.xaxis"
        case .status(let s):  return s.symbol
        }
    }
}