import SwiftUI

struct StatsView: View {
    let stats: LibraryStore.Stats

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headline
                statusBreakdown
                scoreDistribution
                genreCloud
                yearChart

                if stats.total == 0 {
                    Text("还没有记录。点左上角「+」添加第一部番剧。")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: 概览数字

    private var headline: some View {
        HStack(spacing: 12) {
            metricCard("收录番剧", "\(stats.total)", "部", Color.accentColor)
            metricCard("看完", "\(stats.completed)", "部", WatchStatus.completed.tint)
            metricCard("在看", "\(stats.watching)", "部", WatchStatus.watching.tint)
            metricCard("累计集数", "\(stats.episodesWatched)", "集", Color.purple)
            metricCard("平均评分",
                       stats.ratedCount == 0 ? "—" : String(format: "%.1f", stats.averageScore),
                       "分", Color.orange)
        }
    }

    private func metricCard(_ title: String, _ value: String, _ unit: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.secondary.opacity(0.07)))
    }

    // MARK: 状态分布

    private var statusBreakdown: some View {
        VStack(alignment: .leading, spacing: 9) {
            groupLabel("状态分布")
            if stats.total > 0 {
                HStack(spacing: 3) {
                    bar(WatchStatus.completed.tint, stats.completed)
                    bar(WatchStatus.watching.tint, stats.watching)
                    bar(WatchStatus.planToWatch.tint, stats.planToWatch)
                    bar(WatchStatus.dropped.tint, stats.dropped)
                }
                .frame(height: 12)
                .clipShape(Capsule())

                HStack(spacing: 14) {
                    legend(WatchStatus.completed.tint, "看完", stats.completed)
                    legend(WatchStatus.watching.tint, "在看", stats.watching)
                    legend(WatchStatus.planToWatch.tint, "想看", stats.planToWatch)
                    legend(WatchStatus.dropped.tint, "弃番", stats.dropped)
                    Spacer()
                    Text(String(format: "估算观看 %.0f 小时", stats.estimatedHours))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private func bar(_ color: Color, _ value: Int) -> some View {
        if value > 0 {
            Rectangle()
                .fill(color)
                .frame(maxWidth: .infinity)
                .layoutPriority(Double(value))
        }
    }

    private func legend(_ color: Color, _ label: String, _ value: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(label) \(value)")
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 评分分布

    private var scoreDistribution: some View {
        VStack(alignment: .leading, spacing: 9) {
            groupLabel("评分分布")
            if stats.ratedCount == 0 {
                Text("还没有评分过的番剧")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            } else {
                let maxCount = stats.scoreHistogram.values.max() ?? 1
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(1...10, id: \.self) { score in
                        let count = stats.scoreHistogram[score] ?? 0
                        VStack(spacing: 3) {
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Rectangle()
                                .fill(count > 0 ? Color.orange.opacity(0.75) : Color.secondary.opacity(0.12))
                                .frame(height: max(3, CGFloat(count) / CGFloat(maxCount) * 82))
                            Text("\(score)")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 118, alignment: .bottom)
            }
        }
    }

    // MARK: 类型分布

    private var genreCloud: some View {
        VStack(alignment: .leading, spacing: 9) {
            groupLabel("类型偏好")
            if stats.genreCounts.isEmpty {
                Text("还没有类型数据")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            } else {
                let maxCount = stats.genreCounts.first?.1 ?? 1
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(stats.genreCounts, id: \.0) { genre, count in
                        HStack(spacing: 8) {
                            Text(genre)
                                .font(.system(size: 13))
                                .frame(width: 82, alignment: .leading)
                                .lineLimit(1)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Color.secondary.opacity(0.1))
                                    Rectangle()
                                        .fill(Color.accentColor.opacity(0.6))
                                        .frame(width: geo.size.width * CGFloat(count) / CGFloat(maxCount))
                                }
                            }
                            .frame(height: 9)
                            .clipShape(Capsule())

                            Text("\(count)")
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 22, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: 年份分布

    private var yearChart: some View {
        VStack(alignment: .leading, spacing: 9) {
            groupLabel("按年份收录")
            if stats.yearHistogram.isEmpty {
                Text("还没有带年份的记录")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            } else {
                let maxCount = stats.yearHistogram.map(\.1).max() ?? 1
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(stats.yearHistogram, id: \.0) { year, count in
                        VStack(spacing: 3) {
                            Rectangle()
                                .fill(Color.teal.opacity(0.7))
                                .frame(height: max(3, CGFloat(count) / CGFloat(maxCount) * 66))
                            Text(String(year).suffix(2))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 100, alignment: .bottom)
            }
        }
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
    }
}