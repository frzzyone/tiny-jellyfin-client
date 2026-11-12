import JellyfinKit
import SwiftUI

/// Download, its progress, Downloaded, or Try again: a wide button on the detail sheet, an icon on
/// an episode row. Cancelling and deleting ask first.
struct DownloadControl: View {
    enum Style { case wide, icon }

    @Environment(AppModel.self) private var model
    let item: BaseItem
    var style: Style = .wide
    @State private var confirming = false

    private var downloads: Downloads { model.downloads }
    private var record: DownloadRecord? { downloads.record(item.id) }

    var body: some View {
        Group {
            if case .failed(let reason)? = record?.status, style == .wide {
                VStack(spacing: 6) {
                    capsule { Text("Try again") }
                    Text(reason).scaledFont(size: 13).foregroundStyle(Color(red: 1, green: 0.54, blue: 0.5))
                        .multilineTextAlignment(.center)
                }
            } else if style == .wide {
                capsule { HStack(spacing: 8) { icon; Text(label) } }
            } else {
                Button(action: tap) { icon.frame(width: 44, height: 44) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label)
            }
        }
        .disabled(record == nil && !downloads.isOnline)
        .confirmationDialog(item.displayName, isPresented: $confirming, titleVisibility: .visible) {
            if record?.isDone == true {
                Button("Delete Download", role: .destructive) { downloads.delete(item.id) }
            } else {
                Button("Cancel Download", role: .destructive) { downloads.delete(item.id) }
            }
        }
    }

    private func capsule(@ViewBuilder _ content: () -> some View) -> some View {
        Button(action: tap) {
            content()
                .scaledFont(size: 15)
                .foregroundStyle(record == nil || record?.isDone == true ? BrowserStyle.text : BrowserStyle.dim)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(Capsule().stroke(BrowserStyle.line))
        }
    }

    private func tap() {
        switch record?.status {
        case nil: Task { await downloads.download(item) }
        case .failed?: Task { await downloads.tryAgain(item.id) }
        default: confirming = true
        }
    }

    private var label: String {
        guard let record else {
            guard let size = DownloadSize.estimate(item) else { return "Download" }
            return "Download · \(DownloadSize.isOriginal(item) ? "" : "~")\(Self.size(size))"
        }
        switch record.status {
        case .done: return "Downloaded · \(Self.size(record.receivedBytes))"
        case .failed: return "Try again"
        case .queued, .downloading:
            if downloads.waitingForWiFi { return "Waiting for Wi-Fi" }
            if record.status == .queued { return "Queued" }
            return "Downloading · \(Int(downloads.fraction(record) * 100))%"
        }
    }

    @ViewBuilder private var icon: some View {
        switch record?.status {
        case nil:
            Image(systemName: "arrow.down.to.line").foregroundStyle(style == .wide ? BrowserStyle.accent : BrowserStyle.dim)
        case .done?:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(BrowserStyle.accent)
        case .failed?:
            Image(systemName: "exclamationmark.circle").foregroundStyle(Color(red: 1, green: 0.54, blue: 0.5))
        default:
            if downloads.waitingForWiFi {
                Image(systemName: "wifi").foregroundStyle(BrowserStyle.dim)
            } else {
                ProgressRing(fraction: record.map(downloads.fraction) ?? 0)
            }
        }
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// A ring filling with the download, a stop square in the middle (a tap offers Cancel).
struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(BrowserStyle.line, lineWidth: 2)
            Circle().trim(from: 0, to: fraction).stroke(BrowserStyle.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            RoundedRectangle(cornerRadius: 1).fill(BrowserStyle.text).frame(width: 6, height: 6)
        }
        .frame(width: 18, height: 18)
        .animation(.linear(duration: 0.4), value: fraction)
    }
}

/// The Downloads tab: films, then series (opening to their episodes), readable with no connection.
struct PhoneDownloadsView: View {
    @Environment(AppModel.self) private var model
    let onPlay: (BaseItem, Bool) -> Void

    private var records: [DownloadRecord] { model.downloads.records }
    private var films: [DownloadRecord] { records.filter { $0.item.seriesId == nil } }
    /// One entry per series, in the order their first episode arrived.
    private var series: [(id: String, episodes: [DownloadRecord])] {
        var order: [String] = []
        var groups: [String: [DownloadRecord]] = [:]
        for record in records {
            guard let id = record.item.seriesId else { continue }
            if groups[id] == nil { order.append(id) }
            groups[id, default: []].append(record)
        }
        return order.map { ($0, groups[$0]!.sorted(by: Self.episodeOrder)) }
    }

    var body: some View {
        Group {
            if records.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 44)).foregroundStyle(BrowserStyle.line)
                    Text("Nothing downloaded yet").scaledFont(size: 20, weight: .semibold)
                    Text("Tap Download on a film or an episode to watch it without a connection.")
                        .scaledFont(size: 15).foregroundStyle(BrowserStyle.dim)
                    Text(Self.forYouNote).scaledFont(size: 13).foregroundStyle(BrowserStyle.muted)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !films.isEmpty {
                        Section("Films") {
                            ForEach(films) { record in
                                DownloadRow(record: record, title: record.item.displayName, onPlay: onPlay)
                            }
                            .onDelete { delete(films, $0) }
                        }
                    }
                    if !series.isEmpty {
                        Section("Series") {
                            ForEach(series, id: \.id) { group in
                                NavigationLink(value: group.id) {
                                    SeriesDownloadRow(episodes: group.episodes)
                                }
                                .listRowBackground(BrowserStyle.ground)
                            }
                            .onDelete { offsets in
                                for offset in offsets { series[offset].episodes.forEach { model.downloads.delete($0.id) } }
                            }
                        }
                    }
                    Section {
                    } footer: {
                        Text([Self.forYouNote, used.map { "\(DownloadControl.size($0)) on this iPhone." }].compactMap { $0 }.joined(separator: " "))
                            .scaledFont(size: 12.5).foregroundStyle(BrowserStyle.muted)
                    }
                }
                .scrollContentBackground(.hidden)
                .navigationDestination(for: String.self) { seriesId in
                    PhoneDownloadedSeriesView(seriesId: seriesId, onPlay: onPlay)
                }
            }
        }
        .background(BrowserStyle.ground)
        .navigationTitle("Downloads")
    }

    /// Space the finished downloads take; nil until one is.
    private var used: Int64? {
        let done = records.filter(\.isDone)
        return done.isEmpty ? nil : done.reduce(0) { $0 + $1.receivedBytes }
    }

    private func delete(_ list: [DownloadRecord], _ offsets: IndexSet) {
        for offset in offsets { model.downloads.delete(list[offset].id) }
    }

    static let forYouNote = "Tinyfin keeps your next episodes and film ready on Wi-Fi, up to 15 GB."

    static func episodeOrder(_ a: DownloadRecord, _ b: DownloadRecord) -> Bool {
        (a.item.parentIndexNumber ?? 0, a.item.indexNumber ?? 0) < (b.item.parentIndexNumber ?? 0, b.item.indexNumber ?? 0)
    }
}

/// A series' downloaded episodes.
struct PhoneDownloadedSeriesView: View {
    @Environment(AppModel.self) private var model
    let seriesId: String
    let onPlay: (BaseItem, Bool) -> Void

    private var episodes: [DownloadRecord] {
        model.downloads.records.filter { $0.item.seriesId == seriesId }.sorted(by: PhoneDownloadsView.episodeOrder)
    }

    var body: some View {
        List {
            ForEach(episodes) { record in
                DownloadRow(record: record, title: [record.item.indexNumber.map { "\($0)." }, record.item.displayName].compactMap { $0 }.joined(separator: " "),
                            onPlay: onPlay)
            }
            .onDelete { offsets in
                let list = episodes
                for offset in offsets { model.downloads.delete(list[offset].id) }
            }
            Section {
            } footer: {
                Text("When you finish an episode it is deleted, and the next one downloads on Wi-Fi.")
                    .scaledFont(size: 12.5).foregroundStyle(BrowserStyle.muted)
            }
        }
        .scrollContentBackground(.hidden)
        .background(BrowserStyle.ground)
        .navigationTitle(episodes.first?.item.seriesName ?? "Series")
    }
}

/// A download in a list: poster, title, what it is or how far along, and "Downloaded for you".
/// A finished one plays on a tap.
struct DownloadRow: View {
    @Environment(AppModel.self) private var model
    let record: DownloadRecord
    let title: String
    let onPlay: (BaseItem, Bool) -> Void

    var body: some View {
        Button {
            if record.isDone { onPlay(record.item, true) }
        } label: {
            HStack(spacing: 12) {
                DownloadPoster(record: record)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).scaledFont(size: 16, weight: .semibold).foregroundStyle(BrowserStyle.text).lineLimit(2)
                    Text(DownloadRow.detail(record, model.downloads)).scaledFont(size: 13).foregroundStyle(BrowserStyle.muted)
                    if record.isDone, let pct = record.item.userData?.playedPercentage, pct > 0 {
                        ProgressLine(fraction: pct / 100).clipShape(Capsule()).padding(.top, 3)
                    }
                    if record.kind == .forYou {
                        Text("Downloaded for you").scaledFont(size: 12.5).foregroundStyle(BrowserStyle.accent)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(BrowserStyle.ground)
    }

    @MainActor static func detail(_ record: DownloadRecord, _ downloads: Downloads) -> String {
        switch record.status {
        case .done:
            return [record.item.runtimeMinutes.map(ItemLabels.minutes), DownloadControl.size(record.receivedBytes)]
                .compactMap { $0 }.joined(separator: " · ")
        case .failed(let reason): return reason
        case .queued, .downloading:
            if downloads.waitingForWiFi { return "Waiting for Wi-Fi" }
            if record.status == .queued { return "Queued" }
            return "Downloading · \(Int(downloads.fraction(record) * 100))% of \(DownloadControl.size(record.expectedBytes))"
        }
    }
}

struct SeriesDownloadRow: View {
    @Environment(AppModel.self) private var model
    let episodes: [DownloadRecord]

    var body: some View {
        HStack(spacing: 12) {
            DownloadPoster(record: episodes[0])
            VStack(alignment: .leading, spacing: 3) {
                Text(episodes[0].item.seriesName ?? "").scaledFont(size: 16, weight: .semibold).foregroundStyle(BrowserStyle.text)
                Text(summary).scaledFont(size: 13).foregroundStyle(BrowserStyle.muted)
                if episodes.allSatisfy({ $0.kind == .forYou }) {
                    Text("Downloaded for you").scaledFont(size: 12.5).foregroundStyle(BrowserStyle.accent)
                }
            }
        }
    }

    private var summary: String {
        if episodes.count == 1 {
            let only = episodes[0]
            return only.isDone ? [only.item.episodeLabel?.replacingOccurrences(of: " · ", with: " "), DownloadControl.size(only.receivedBytes)].compactMap { $0 }.joined(separator: " · ")
                : DownloadRow.detail(only, model.downloads)
        }
        let bytes = episodes.reduce(Int64(0)) { $0 + ($1.isDone ? $1.receivedBytes : $1.expectedBytes) }
        return "\(episodes.count) episodes · \(DownloadControl.size(bytes))"
    }
}

/// The poster saved with the download (the series' for an episode).
struct DownloadPoster: View {
    @Environment(AppModel.self) private var model
    let record: DownloadRecord

    var body: some View {
        let url = model.downloads.store.file(record.id, LocalPlaybackService.posterFile)
        Artwork(url: FileManager.default.fileExists(atPath: url.path) ? url : nil, title: "", toneID: record.item.seriesId ?? record.id)
            .frame(width: 56, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: BrowserStyle.corner))
    }
}

/// Home with no connection: say so, and offer the downloads.
struct PhoneOfflineNote: View {
    let server: String
    let onGoToDownloads: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash").font(.system(size: 44)).foregroundStyle(BrowserStyle.line)
            Text("You're offline").scaledFont(size: 20, weight: .semibold)
            Text("Can't reach \(server). Your downloads are ready to watch.")
                .scaledFont(size: 15).foregroundStyle(BrowserStyle.dim)
            Button(action: onGoToDownloads) {
                Text("Go to Downloads").scaledFont(size: 16, weight: .semibold).foregroundStyle(BrowserStyle.ground)
                    .padding(.horizontal, 28).frame(minHeight: 48).background(BrowserStyle.accent, in: Capsule())
            }
            Button(action: onRetry) {
                Text("Try again").scaledFont(size: 15).foregroundStyle(BrowserStyle.text)
                    .padding(.horizontal, 22).frame(minHeight: 44).overlay(Capsule().stroke(BrowserStyle.line))
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 44)
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }
}
