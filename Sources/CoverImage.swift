import Foundation
import SwiftUI
import AppKit

/// 封面两级缓存：内存 NSCache + 磁盘文件。避免重复下载，也保证离线时仍能显示。
actor CoverCache {
    static let shared = CoverCache()

    private let memory = NSCache<NSURL, NSImage>()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    private func fileURL(for remote: URL) -> URL {
        // 注意：不能用 URL.hashValue —— Swift 的哈希带随机种子，进程间不稳定，
        // 会导致每次启动都判定缓存失效、重复下载并堆积垃圾文件。
        // 这里用 FNV-1a 做确定性哈希，同一 URL 永远得到同一文件名。
        let name = Self.stableHash(remote.absoluteString)
        return LibraryStore.coversDirectory.appendingPathComponent("\(name).img")
    }

    /// FNV-1a 32 位哈希，纯函数、跨进程稳定
    nonisolated static func stableHash(_ s: String) -> String {
        var hash: UInt32 = 0x811c9dc5
        for byte in Array(s.utf8) {
            hash ^= UInt32(byte)
            hash = hash &* 0x01000193
        }
        // 再混入长度，进一步降低碰撞概率
        hash ^= UInt32(truncatingIfNeeded: s.utf8.count)
        return String(format: "%08x", hash)
    }

    func image(for urlString: String) async -> NSImage? {
        guard let remote = URL(string: urlString), !urlString.isEmpty else { return nil }

        // 1. 内存
        if let hit = memory.object(forKey: remote as NSURL) { return hit }

        // 2. 磁盘
        let local = fileURL(for: remote)
        if let data = try? Data(contentsOf: local), let img = NSImage(data: data) {
            memory.setObject(img, forKey: remote as NSURL)
            return img
        }

        // 3. 网络
        var request = URLRequest(url: remote)
        request.setValue("AnimeTracker/1.0 (macOS local tracker)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: request),
              let img = NSImage(data: data) else { return nil }

        memory.setObject(img, forKey: remote as NSURL)
        try? FileManager.default.createDirectory(
            at: LibraryStore.coversDirectory, withIntermediateDirectories: true)
        try? data.write(to: local, options: .atomic)
        return img
    }
}

/// 封面加载状态容器。
/// 用 ObservableObject 而非自定义包装器：异步加载完成后能可靠触发视图刷新。
final class CoverLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    private var currentKey = ""

    func load(_ urlString: String) {
        guard urlString != currentKey else { return }
        currentKey = urlString

        guard !urlString.isEmpty, URL(string: urlString) != nil else {
            image = nil
            return
        }
        // 命中同步缓存时立即显示，避免闪一下占位图
        image = nil
        Task { @MainActor [weak self] in
            let loaded = await CoverCache.shared.image(for: urlString)
            guard let self, self.currentKey == urlString else { return }
            self.image = loaded
        }
    }
}

/// 异步加载封面的 SwiftUI 视图（固定尺寸）。
struct CoverImage: View {
    let urlString: String
    var width: CGFloat
    var height: CGFloat

    @StateObject private var loader = CoverLoader()

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.08))

            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "film")
                    .font(.system(size: min(width, height) * 0.22))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onAppear { loader.load(urlString) }
        .onChange(of: urlString) { _, new in loader.load(new) }
    }
}

/// 详情面板用的大封面，按可用宽度自适应高度。
/// 用 aspectRatio 而非固定 frame，避免溢出遮挡下方控件。
struct FlexibleCover: View {
    let urlString: String

    @StateObject private var loader = CoverLoader()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))

            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "film")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    if !urlString.isEmpty {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
        .aspectRatio(1 / 1.42, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear { loader.load(urlString) }
        .onChange(of: urlString) { _, new in loader.load(new) }
    }
}