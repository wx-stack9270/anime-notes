import Foundation

/// 番剧库在线补充。
///
/// 重要约束（已实测验证）：Bangumi 免费 API **不支持分页与日期区间查询**
/// - `GET /v0/subjects?type=2&page=N` → page 参数无效，任何页码都返回同一批 30 条
/// - `POST /v0/search/subjects` 的 limit → 传 20/50/100 均只返回 10 条
/// - `air_date` 区间筛选 → HTTP 400
/// - `/anime` 端点 → 404
///
/// 因此无法穷举全库（总量 29598 条）。内置目录由离线精选数据集提供，
/// 本 actor 只负责按关键词实时补充用户主动搜索的番剧。
enum CatalogSync {

    struct SearchHit: Identifiable, Hashable {
        var id: Int { entry.id }
        var entry: CatalogEntry
    }

    /// 搜索番剧并转为目录条目，供「补充到目录」使用
    static func search(_ keyword: String, limit: Int = 10) async -> [CatalogEntry] {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let url = URL(string: "https://api.bgm.tv/v0/search/subjects") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AnimeTracker/1.0 (macOS local tracker)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "keyword": trimmed,
            "filter": ["type": [2]],
            "limit": limit
        ])

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return [] }
        return decodeEntries(data)
    }

    /// 批量搜索多个关键词并合并去重，用于扩充内置目录
    static func searchMany(_ keywords: [String]) async -> [CatalogEntry] {
        var seen: Set<Int> = []
        var result: [CatalogEntry] = []

        for kw in keywords {
            let items = await search(kw)
            for item in items where !seen.contains(item.id) {
                seen.insert(item.id)
                result.append(item)
            }
        }
        return result
    }

    // MARK: - 解码

    private struct Page: Decodable {
        var data: [Item]?
    }

    private struct Item: Decodable {
        var id: Int
        var name: String?
        var name_cn: String?
        var summary: String?
        var date: String?
        var eps: Int?
        var images: Images?
        var meta_tags: [String]?

        struct Images: Decodable {
            var large: String?
            var common: String?
        }
    }

    /// 非题材分类：地区、媒介类型等，不适合当题材标签
    private static let nonGenre: Set<String> = [
        "TV", "Web", "剧场版", "TV版", "OVA", "OAD", "动画",
        "日本", "欧美", "中国", "韩国", "台湾", "香港", "东南亚",
    ]

    private static func decodeEntries(_ data: Data) -> [CatalogEntry] {
        guard let page = try? JSONDecoder().decode(Page.self, from: data),
              let items = page.data else { return [] }

        var out: [CatalogEntry] = []
        for item in items {
            let title = (item.name_cn ?? "").trimmingCharacters(in: .whitespaces)
            let original = (item.name ?? "").trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty || !original.isEmpty else { continue }

            let summary = (item.summary ?? "")
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let genres = (item.meta_tags ?? [])
                .filter { !nonGenre.contains($0) && !$0.hasPrefix("19") && !$0.hasPrefix("20") }
                .prefix(5)
                .map { $0 }

            out.append(CatalogEntry(
                id: item.id,
                title: title.isEmpty ? original : title,
                originalTitle: original,
                coverURL: item.images?.large ?? item.images?.common ?? "",
                summary: summary,
                airDate: item.date ?? "",
                totalEpisodes: item.eps ?? 0,
                genres: genres,
                rank: 0
            ))
        }
        return out
    }
}