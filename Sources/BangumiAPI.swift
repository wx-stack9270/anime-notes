import Foundation

/// Bangumi 公开 API 封装。失败时一律返回空结果，绝不影响本地记录功能。
struct BangumiAPI {

    struct SearchItem: Identifiable, Hashable {
        var id: Int
        var title: String
        var originalTitle: String
        var summary: String
        var coverURL: String
        var totalEpisodes: Int
        var genres: [String]
        var year: Int

        /// 转成本地记录，状态由调用方决定
        func makeAnime(status: WatchStatus) -> Anime {
            var a = Anime()
            a.title = title
            a.originalTitle = originalTitle
            a.summary = summary
            a.coverURL = coverURL
            a.totalEpisodes = totalEpisodes
            a.genres = genres
            a.year = year
            a.status = status
            return a
        }
    }

    private struct SearchResponse: Decodable {
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
        var tags: [Tag]?
        /// 权威分类标签（题材、改编来源、地区），不含制作公司与主创人员
        var meta_tags: [String]?

        struct Images: Decodable {
            var large: String?
            var common: String?
            var medium: String?
        }
        struct Tag: Decodable {
            var name: String
        }
    }


    /// 搜索番剧。type 2 = 动画。
    static func search(_ keyword: String, limit: Int = 12) async -> [SearchItem] {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 1 else { return [] }

        guard let url = URL(string: "https://api.bgm.tv/v0/search/subjects") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AnimeTracker/1.0 (macOS local tracker)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "keyword": trimmed,
            "filter": ["type": [2]],
            "limit": limit
        ])

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(SearchResponse.self, from: data),
              let items = response.data else {
            return []
        }

        return items.compactMap { (item: Item) -> SearchItem? in
            let title = item.name_cn?.trimmingCharacters(in: .whitespaces) ?? ""
            let original = item.name?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !title.isEmpty || !original.isEmpty else { return nil }

            // 简介压成单行，表格里更好读
            let summary = (item.summary ?? "")
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // 标签用 meta_tags：它是 Bangumi 的官方分类（题材/改编/地区），
            // 已经排除了制作公司与主创人员，无需再做启发式过滤。
            // tags 字段里全是「远藤达哉」「KINEMA_CITRUS」这类噪声，不可用。
            let genreOrder = ["日常", "奇幻", "科幻", "热血", "悬疑", "冒险", "动作",
                              "爱情", "喜剧", "治愈", "校园", "宫廷", "历史",
                              "机甲", "末世", "美食", "音乐", "运动", "推理",
                              "神话", "古风", "黑白", "赌博", "职场", "媒体"]

            let raw = item.meta_tags ?? []
            // 去掉地区与平台这类非题材分类
            let regions: Set<String> = ["日本", "欧美", "中国", "韩国", "TV", "Web",
                                       "剧场版", "TV版", "动画", "儿童", "青年"]
            let genres = Array(raw
                .filter { !regions.contains($0) }
                // 题材词排前面，其余按原序
                .sorted { a, b in
                    let ia = genreOrder.firstIndex(of: a) ?? Int.max
                    let ib = genreOrder.firstIndex(of: b) ?? Int.max
                    return ia < ib
                }
                .prefix(5))

            // date 形如 "2022-04-09"，部分条目为空
            let year = Int(item.date?.prefix(4) ?? "") ?? 0

            return SearchItem(
                id: item.id,
                title: title.isEmpty ? original : title,
                originalTitle: original,
                summary: summary,
                coverURL: item.images?.large ?? item.images?.common ?? item.images?.medium ?? "",
                totalEpisodes: item.eps ?? 0,
                genres: genres,
                year: year
            )
        }
    }

    /// 搜索响应已自带 eps，无需再请求详情接口。
}