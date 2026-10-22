import SwiftUI

// MARK: - 卡片（网格模式）

struct AnimeCardView: View {
    let anime: Anime
    let isSelected: Bool
    let onSelect: () -> Void
    let onBumpProgress: () -> Void
    let onSetStatus: (WatchStatus) -> Void

    @LocalState private var isHovering = false

    private let coverWidth: CGFloat = 138
    private var coverHeight: CGFloat { coverWidth * 1.42 }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomLeading) {
                CoverImage(urlString: anime.coverURL, width: coverWidth, height: coverHeight)

                if anime.totalEpisodes > 0 && anime.status != .planToWatch {
                    // 进度条压封面底部，玻璃描边与填充
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.black.opacity(0.4))
                            Rectangle()
                                .fill(anime.status.tint)
                                .frame(width: geo.size.width * anime.progressRatio)
                        }
                        .frame(height: 3)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }

                // 收藏：玻璃药丸而非实心图标。
                // 封面本身已是彩色内容，玻璃在其上折射不明显，
                // 故补一层半透明底保证图标可读
                if anime.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .padding(4)
                        .glassEffect(Glass.regular, in: .circle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(5)
                }

                // 集数角标：悬浮时显示，方便不点进去就看进度
                if isHovering && anime.totalEpisodes > 0 {
                    Text("\(anime.watchedEpisodes)/\(anime.totalEpisodes)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background { Capsule().fill(.black.opacity(0.55)) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(5)
                }
            }
            .frame(width: coverWidth, height: coverHeight)
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlass.Radius.sm, style: .continuous))
            .overlay {
                // 选中态：主题色玻璃环
                RoundedRectangle(cornerRadius: LiquidGlass.Radius.sm, style: .continuous)
                    .strokeBorder(
                        isSelected ? anime.status.tint : .white.opacity(isHovering ? 0.35 : 0),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .shadow(
                color: .black.opacity(isHovering ? 0.16 : 0.06),
                radius: isHovering ? 12 : 5,
                y: isHovering ? 5 : 2
            )
            .scaleEffect(isHovering ? 1.025 : 1.0)
            .animation(LiquidGlass.Motion.lift, value: isHovering)

            VStack(alignment: .leading, spacing: 3) {
                Text(anime.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    // 状态胶囊：玻璃底 + 彩色点
                    HStack(spacing: 3) {
                        Circle().fill(anime.status.tint).frame(width: 5, height: 5)
                        Text(anime.status.displayName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background { Capsule().fill(.primary.opacity(0.06)) }

                    Text(anime.progressText)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)

                    Spacer(minLength: 2)

                    if anime.score > 0 {
                        HStack(spacing: 1.5) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                            Text("\(anime.score)")
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(width: coverWidth, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .animation(LiquidGlass.Motion.standard, value: isSelected)
        .contextMenu { contextMenuContent }
        .help("\(anime.displayTitle)\(anime.totalEpisodes > 0 ? " · 共 \(anime.totalEpisodes) 集" : "")")
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Button("看过的集数 +1", systemImage: "plus.circle") { onBumpProgress() }
        Button("标记为看完", systemImage: "checkmark.circle") { onSetStatus(.completed) }
        Divider()
        ForEach(WatchStatus.allCases) { status in
            Button {
                onSetStatus(status)
            } label: {
                Label("标为「\(status.displayName)」", systemImage: status.symbol)
            }
        }
    }
}

// MARK: - 行（列表模式）

struct AnimeRowView: View {
    let anime: Anime
    let isSelected: Bool
    let onSelect: () -> Void
    let onBumpProgress: () -> Void
    let onSetStatus: (WatchStatus) -> Void

    @LocalState private var isHovering = false

    var body: some View {
        // 玻璃作为独立底层视图，内容叠加其上。
        // 直接 <内容>.glassEffect(...) 会吞掉整棵子树，导致文字消失。
        HStack(spacing: LiquidGlass.Space.md) {
            CoverImage(urlString: anime.coverURL, width: 34, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(anime.displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle().fill(anime.status.tint).frame(width: 6, height: 6)
                    Text(anime.status.displayName)
                        .font(.system(size: 13))
                    Text("·")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                    Text(anime.progressText)
                        .font(.system(size: 13))
                        .monospacedDigit()
                    if !anime.genres.isEmpty {
                        Text("·")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                        Text(anime.genres.prefix(2).joined(separator: " / "))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: LiquidGlass.Space.sm)

            if anime.score > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text("\(anime.score)")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background { Capsule().fill(.primary.opacity(0.06)) }
            }

            Button {
                onBumpProgress()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(isHovering ? anime.status.tint : .secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0.55)
            .help("看过的集数 +1")
        }
        .padding(.horizontal, LiquidGlass.Space.md)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                Color.clear
                    .glassEffect(
                        LiquidGlass.tinted(anime.status.tint),
                        in: .rect(cornerRadius: LiquidGlass.Radius.sm, style: .continuous)
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .animation(LiquidGlass.Motion.standard, value: isSelected)
        .contextMenu { contextMenuContent }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Button("看过的集数 +1", systemImage: "plus.circle") { onBumpProgress() }
        Button("标记为看完", systemImage: "checkmark.circle") { onSetStatus(.completed) }
        Divider()
        ForEach(WatchStatus.allCases) { status in
            Button {
                onSetStatus(status)
            } label: {
                Label("标为「\(status.displayName)」", systemImage: status.symbol)
            }
        }
    }
}
