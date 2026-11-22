import SwiftUI

struct PostInfoView: View {
    let post: Rule34Post
    let sourceMode: Rule34SourceMode
    let onSearchTag: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tagsByCategory: [Rule34TagInfo.Category: [Rule34TagInfo]] = [:]
    @State private var comments: [Rule34Comment] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let api = Rule34APIClient()
    private let tagStore = Rule34TagMetadataStore.shared
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if isLoading {
                        ProgressView()
                            .tint(.orange)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if let errorMessage {
                        R34EmptyStateView(title: "Info not available", systemImage: "info.circle", message: errorMessage)
                    } else {
                        tagSections
                        commentsSection
                    }
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Info")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .automatic) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                #else
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                #endif
            }
            .task(id: post.id) {
                await load()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Post \(post.id)")
                    .font(.headline)
                Spacer()
                let displayMode = post.sourceMode ?? sourceMode
                Text(displayMode == .api ? "API (native r34)" : "Booru (rule34.xxx)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(displayMode == .api ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                    .foregroundStyle(displayMode == .api ? .blue : .green)
                    .clipShape(Capsule())
            }
            HStack(spacing: 12) {
                Label(post.mediaKind, systemImage: post.isVideo ? "play.rectangle.fill" : "photo")
                if let score = post.score {
                    Label(score, systemImage: "hand.thumbsup.fill")
                }
                Text(post.pixelSizeText)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .r34Glass(cornerRadius: 20, interactive: true)
    }

    private var tagSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Rule34TagInfo.Category.allCases, id: \.self) { category in
                if let items = tagsByCategory[category], !items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(category.displayName)
                            .font(.headline)
                        FlowTagsView(tags: items) { tag in
                            onSearchTag(tag)
                        }
                    }
                }
            }
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comments")
                .font(.headline)

            if comments.isEmpty {
                Text("No comments found.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                VStack(spacing: 10) {
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Button {
                                    let creator = comment.creator.isEmpty ? "Anonymous" : comment.creator
                                    onSearchTag(creator)
                                    dismiss()
                                } label: {
                                    Text(comment.creator.isEmpty ? "Anonymous" : comment.creator)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                                .buttonStyle(.plain)

                                Spacer()
                                if let createdAt = comment.createdAt {
                                    Text(createdAt)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(comment.body.decodingHTMLEntities())
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                        .padding(12)
                        .r34Glass(cornerRadius: 16, interactive: true)
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let commentsTask = fetchComments()
        async let tagTask = buildGroupedTags()

        comments = (try? await commentsTask) ?? []
        tagsByCategory = await tagTask

        if comments.isEmpty && tagsByCategory.isEmpty {
            errorMessage = NSLocalizedString("No info returned from the API.", comment: "Post info error")
        }
    }

    private func fetchComments() async throws -> [Rule34Comment] {
        switch sourceMode {
        case .api:
            return try await api.fetchComments(postID: post.id, userID: settings.userID, apiKey: settings.apiKey)
        case .booru:
            let booruComments = try await api.fetchBooruComments(postID: post.id)
            if !booruComments.isEmpty {
                return booruComments
            }
            return (try? await api.fetchComments(postID: post.id, userID: settings.userID, apiKey: settings.apiKey)) ?? []
        }
    }

    private func buildGroupedTags() async -> [Rule34TagInfo.Category: [Rule34TagInfo]] {
        var grouped: [Rule34TagInfo.Category: [Rule34TagInfo]] = [:]
        let tagNames = post.tagList
        let uniqueNames = Array(NSOrderedSet(array: tagNames)) as? [String] ?? tagNames

        // In booru mode the post HTML already tells us the category. Prefer it over
        // autocomplete, which may be unavailable or return incomplete metadata.
        let locallyCategorized = uniqueNames.compactMap { name -> Rule34TagInfo? in
            guard let type = post.tagTypes?[name] else { return nil }
            return Rule34TagInfo(id: name, name: name, count: nil, type: type)
        }
        for info in locallyCategorized {
            grouped[info.category, default: []].append(info)
        }

        let unresolvedNames = uniqueNames.filter { post.tagTypes?[$0] == nil }
        // Avoid starting dozens of autocomplete requests when opening Info.
        // Remaining tags are still shown under General below.
        let lookupTags = Array(unresolvedNames.prefix(12))
        let infos = await tagStore.warm(tags: lookupTags)

        for info in infos {
            if !info.name.isEmpty {
                grouped[info.category, default: []].append(info)
            }
        }

        let categorizedNames = Set(grouped.values.flatMap { $0.map(\.name) })
        let missingNames = uniqueNames.filter { !categorizedNames.contains($0) }
        if !missingNames.isEmpty {
            grouped[.general, default: []].append(contentsOf: missingNames.map {
                Rule34TagInfo(id: $0, name: $0, count: nil, type: nil)
            })
        }

        for category in grouped.keys {
            grouped[category]?.sort { lhs, rhs in
                guard let lhsIndex = uniqueNames.firstIndex(of: lhs.name),
                      let rhsIndex = uniqueNames.firstIndex(of: rhs.name) else { return lhs.name < rhs.name }
                return lhsIndex < rhsIndex
            }
        }

        return grouped
    }
}

private struct FlowTagsView: View {
    let tags: [Rule34TagInfo]
    let onTap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(tags) { tag in
                Button {
                    onTap(tag.name)
                } label: {
                    Text(tag.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(.orange.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}
