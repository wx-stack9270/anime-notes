import SwiftUI
import AppKit

/// 新增 / 编辑弹窗。带联网搜索（自动补全封面、中文集数、简介）+ 纯手动录入两条路。
struct AnimeEditorView: View {
    @ObservedObject var store: LibraryStore
    var existing: Anime?

    @Environment(\.dismiss) private var dismiss

    @LocalState private var draft: Anime = Anime()
    @LocalState private var keyword = ""
    @LocalState private var results: [BangumiAPI.SearchItem] = []
    @LocalState private var isSearching = false
    @LocalState private var searchFailed = false
    @LocalState private var hasSearched = false

    private var isEditingExisting: Bool { existing != nil }

    init(store: LibraryStore, existing: Anime? = nil) {
        self.store = store
        self.existing = existing
        _draft = LocalState(initialValue: existing ?? Anime())
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !isEditingExisting && store.isOnlineLookupEnabled {
                        AnimeSearchSection(
                            keyword: $keyword,
                            results: $results,
                            isSearching: $isSearching,
                            searchFailed: $searchFailed,
                            hasSearched: $hasSearched,
                            onPick: apply
                        )
                        Divider()
                    }
                    AnimeFormSection(draft: $draft)
                }
                .padding(18)
            }

            Divider()
            footerBar
        }
        .frame(width: 560, height: 620)
        .task {
            if isEditingExisting {
                await backfillEpisodes()
            }
        }
    }

    // MARK: 标题栏

    private var headerBar: some View {
        HStack {
            Text(isEditingExisting ? "编辑番剧" : "添加番剧")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: 联网搜索

    private func apply(_ result: BangumiAPI.SearchItem) {
        var copy = draft
        copy.title = result.title
        copy.originalTitle = result.originalTitle
        copy.summary = result.summary
        copy.coverURL = result.coverURL
        copy.genres = result.genres
        copy.year = result.year
        if result.totalEpisodes > 0 {
            copy.totalEpisodes = result.totalEpisodes
        }
        draft = copy
    }

    private func performSearch() async {
        let q = keyword.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        searchFailed = false
        let found = await BangumiAPI.search(q)
        results = found
        searchFailed = found.isEmpty
        hasSearched = true
        isSearching = false
    }

    /// 编辑已有条目时，若本地没记集数，联网补一次
    private func backfillEpisodes() async {
        guard store.isOnlineLookupEnabled, draft.totalEpisodes == 0 else { return }
        let q = draft.displayTitle
        guard !q.isEmpty else { return }
        let found = await BangumiAPI.search(q, limit: 3)
        if let match = found.first(where: { $0.title == draft.displayTitle }) ?? found.first,
           match.totalEpisodes > 0 {
            var copy = draft
            copy.totalEpisodes = match.totalEpisodes
            draft = copy
        }
    }

    // MARK: 底部

    private var footerBar: some View {
        HStack {
            if let existing {
                Button(role: .destructive) {
                    store.delete(existing)
                    dismiss()
                } label: {
                    Text("删除")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

            Spacer()

            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("保存") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.displayTitle.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func save() {
        if isEditingExisting {
            store.update(draft)
        } else {
            store.add(draft)
        }
        dismiss()
    }
}

// MARK: - 搜索区块

private struct AnimeSearchSection: View {
    @Binding var keyword: String
    @Binding var results: [BangumiAPI.SearchItem]
    @Binding var isSearching: Bool
    @Binding var searchFailed: Bool
    @Binding var hasSearched: Bool
    let onPick: (BangumiAPI.SearchItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("联网搜索")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                if isSearching {
                    ProgressView().controlSize(.small)
                }
            }

            HStack(spacing: 6) {
                TextField("输入番剧名，回车搜索", text: $keyword)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await runSearch() } }

                Button("搜索") {
                    Task { await runSearch() }
                }
                .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }

            if searchFailed {
                Label("搜索失败，检查网络后重试；也可以直接手动填写。", systemImage: "wifi.exclamationmark")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
            }

            if !results.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(results) { result in
                            resultRow(result)
                        }
                    }
                }
                .frame(maxHeight: 200)
            } else if !isSearching && searchFailed == false && hasSearched {
                Text("没有找到匹配的番剧")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }

            Text("提示：搜索会从 Bangumi 拉取封面、中文名、集数与简介，选中即自动填入。")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    private func runSearch() async {
        let q = keyword.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        searchFailed = false
        let found = await BangumiAPI.search(q)
        results = found
        searchFailed = found.isEmpty
        hasSearched = true
        isSearching = false
    }

    private func resultRow(_ result: BangumiAPI.SearchItem) -> some View {
        Button {
            onPick(result)
        } label: {
            HStack(spacing: 9) {
                CoverImage(urlString: result.coverURL, width: 34, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if !result.originalTitle.isEmpty {
                            Text(result.originalTitle)
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                        if result.year > 0 {
                            Text("· \(result.year)")
                                .font(.system(size: 12))
                        }
                        if !result.genres.isEmpty {
                            Text("· \(result.genres.prefix(2).joined(separator: "/"))")
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if result.totalEpisodes > 0 {
                    Text("\(result.totalEpisodes) 集")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 表单区块

private struct AnimeFormSection: View {
    @Binding var draft: Anime
    @LocalState private var newGenre = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 5) {
                    CoverImage(urlString: draft.coverURL, width: 78, height: 110)
                    Button(draft.coverURL.isEmpty ? "选封面图" : "更换封面") {
                        pickCover()
                    }
                    .controlSize(.mini)
                }

                VStack(alignment: .leading, spacing: 9) {
                    labeledField("中文名") {
                        TextField("例：葬送的芙莉莲", text: $draft.title)
                            .textFieldStyle(.roundedBorder)
                    }

                    labeledField("日文原名") {
                        TextField("可留空", text: $draft.originalTitle)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 9) {
                        labeledField("总集数") {
                            TextField("0", value: $draft.totalEpisodes, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                        labeledField("放送年份") {
                            TextField("0", value: $draft.year, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }

            labeledField("观看状态") {
                Picker("", selection: $draft.status) {
                    ForEach(WatchStatus.allCases) { status in
                        Label(status.displayName, systemImage: status.symbol).tag(status)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            labeledField("已看集数") {
                HStack(spacing: 8) {
                    Stepper("", value: $draft.watchedEpisodes, in: 0...9999)
                    if draft.totalEpisodes > 0 {
                        Text("/ \(draft.totalEpisodes) 集")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("类型标签")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                if !draft.genres.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(draft.genres, id: \.self) { genre in
                            genreChip(genre)
                        }
                    }
                }

                HStack(spacing: 6) {
                    TextField("添加标签后回车", text: $newGenre)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addGenre)
                    Button("添加", action: addGenre)
                        .disabled(newGenre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            labeledField("简介") {
                TextEditor(text: $draft.summary)
                    .font(.system(size: 13))
                    .frame(height: 76)
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
            }

            labeledField("备注") {
                TextEditor(text: $draft.notes)
                    .font(.system(size: 13))
                    .frame(height: 56)
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
            }
        }
    }

    private func genreChip(_ genre: String) -> some View {
        HStack(spacing: 3) {
            Text(genre)
                .font(.system(size: 13))
            Button {
                draft.genres.removeAll { $0 == genre }
            } label: {
                Image(systemName: "xmark").font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }

    private func addGenre() {
        let value = newGenre.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !draft.genres.contains(value) else {
            newGenre = ""
            return
        }
        draft.genres.append(value)
        newGenre = ""
    }

    private func pickCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .webP]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // 复制到应用缓存目录，避免原图被移动或删除后失效
        let destDir = LibraryStore.coversDirectory.appendingPathComponent("local", isDirectory: true)
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let dest = destDir.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try? FileManager.default.copyItem(at: url, to: dest)
        draft.coverURL = "file://" + dest.path
    }

    private func labeledField<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}