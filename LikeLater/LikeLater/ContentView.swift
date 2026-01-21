//
//  ContentView.swift
//  LikeLater
//
//  Created by jihoon_macbook_air_13_m2 on 1/21/26.
//

import SwiftUI
import Combine

struct ContentView: View {
    @ObservedObject var store: QueueStore
    @ObservedObject var spotify: SpotifyService

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    if let event = store.lastEvent {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.lastMessage)
                                .font(.headline)
                            Text(event.rawURL)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text("Received: \(formatDate(event.receivedAt))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No capture yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Queue") {
                    if store.items.isEmpty {
                        Text("Queue is empty.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.platformHint ?? "unknown")
                                    .font(.headline)
                                Text("Source: \(item.source) • \(formatDate(item.capturedAt))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                if let note = item.note, !note.isEmpty {
                                    Text(note)
                                        .font(.footnote)
                                }
                                if let matchedTrack = item.matchedTrack, !matchedTrack.isEmpty {
                                    Text("Matched: \(matchedTrack)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Matched: not yet")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Text("Status: \(item.status)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Text("Match Status: \(item.matchStatus)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Storage") {
                    Text(store.storageDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Spotify") {
                    Text(spotify.lastStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Connect Spotify") {
                        spotify.startAuthorization()
                    }
                    Button("Fetch Recently Played") {
                        Task {
                            await spotify.fetchRecentlyPlayed(into: store)
                        }
                    }
                }

            }
            .navigationTitle("LikeLater Queue")
        }
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().hour().minute().second())
    }
}

#Preview {
    ContentView(store: QueueStore(preview: true), spotify: SpotifyService())
}

struct QueueItem: Identifiable, Codable, Equatable {
    let id: UUID
    let capturedAt: Date
    let source: String
    let platformHint: String?
    let note: String?
    let status: String
    var matchStatus: String
    var matchedTrack: String?

    init(
        id: UUID,
        capturedAt: Date,
        source: String,
        platformHint: String?,
        note: String?,
        status: String,
        matchStatus: String = "pending",
        matchedTrack: String? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.source = source
        self.platformHint = platformHint
        self.note = note
        self.status = status
        self.matchStatus = matchStatus
        self.matchedTrack = matchedTrack
    }

    enum CodingKeys: String, CodingKey {
        case id
        case capturedAt
        case createdAt
        case source
        case platformHint
        case note
        case status
        case matchStatus
        case matchedTrack
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        if let capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt) {
            self.capturedAt = capturedAt
        } else if let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) {
            self.capturedAt = createdAt
        } else {
            self.capturedAt = Date()
        }
        source = try container.decode(String.self, forKey: .source)
        platformHint = try container.decodeIfPresent(String.self, forKey: .platformHint)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        status = try container.decode(String.self, forKey: .status)
        matchStatus = try container.decodeIfPresent(String.self, forKey: .matchStatus) ?? "pending"
        matchedTrack = try container.decodeIfPresent(String.self, forKey: .matchedTrack)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(platformHint, forKey: .platformHint)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(status, forKey: .status)
        try container.encode(matchStatus, forKey: .matchStatus)
        try container.encodeIfPresent(matchedTrack, forKey: .matchedTrack)
    }
}

struct CaptureEvent: Codable, Equatable {
    let receivedAt: Date
    let rawURL: String
    let query: [String: String]
}

@MainActor
final class QueueStore: ObservableObject {
    @Published private(set) var items: [QueueItem] = []
    @Published private(set) var lastEvent: CaptureEvent?
    @Published private(set) var lastMessage: String = "Ready to capture."

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(preview: Bool = false) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let value = ISO8601DateFormatter.queueFormatter.string(from: date)
            try container.encode(value)
        }
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if let date = ISO8601DateFormatter.queueFormatter.date(from: rawValue) {
                return date
            }
            if let date = ISO8601DateFormatter.spotifyFormatter.date(from: rawValue) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(rawValue)")
        }
        self.decoder = decoder

        if preview {
            let sample = QueueItem(
                id: UUID(),
                capturedAt: Date(),
                source: "backtap",
                platformHint: "spotify",
                note: "Sample capture",
                status: "pending"
            )
            items = [sample]
            lastEvent = CaptureEvent(
                receivedAt: Date(),
                rawURL: "likelater://capture?source=backtap&app=spotify",
                query: ["source": "backtap", "app": "spotify"]
            )
            lastMessage = "Added to queue."
        } else {
            load()
        }
    }

    var storageDescription: String {
        "Application Support/LikeLater/queue.json"
    }

    func handle(url: URL) -> UUID? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let action = actionName(from: components)
        let query = queryDictionary(from: components)

        lastEvent = CaptureEvent(
            receivedAt: Date(),
            rawURL: url.absoluteString,
            query: query
        )

        switch action {
        case "capture":
            let item = QueueItem(
                id: UUID(),
                capturedAt: Date(),
                source: query["source"] ?? "unknown",
                platformHint: query["app"] ?? query["platform"],
                note: query["note"],
                status: "pending",
                matchStatus: "processing"
            )
            items.insert(item, at: 0)
            lastMessage = "Added to queue."
            save()
            return item.id
        case "openQueue":
            lastMessage = "Opened queue."
            return nil
        case "":
            lastMessage = "No action found in URL."
            return nil
        default:
            lastMessage = "Unknown action: \(action)"
            return nil
        }
    }

    private func actionName(from components: URLComponents?) -> String {
        if let host = components?.host, !host.isEmpty {
            return host
        }
        let path = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        return path
    }

    private func queryDictionary(from components: URLComponents?) -> [String: String] {
        var result: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            result[item.name] = item.value ?? ""
        }
        return result
    }

    private func load() {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: url)
            items = try decoder.decode([QueueItem].self, from: data)
        } catch {
            lastMessage = "Failed to load queue."
        }
    }

    private func save() {
        let url = fileURL()
        do {
            let data = try encoder.encode(items)
            try data.write(to: url, options: [.atomic])
        } catch {
            lastMessage = "Failed to save queue."
        }
    }

    func applyMatchResult(for id: UUID, matchedTrack: String?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if let matchedTrack, !matchedTrack.isEmpty {
            items[index].matchStatus = "matched"
            items[index].matchedTrack = matchedTrack
        } else {
            items[index].matchStatus = "pending"
        }
        save()
    }

    func removeCapture(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    private func fileURL() -> URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent("LikeLater", isDirectory: true)

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL.appendingPathComponent("queue.json")
    }

    // MARK: - Matching Skeleton
    func applyRecentPlays(_ plays: [RecentlyPlayedItem]) {
        guard !plays.isEmpty else { return }

        let sortedPlays = plays.sorted { $0.playedAt < $1.playedAt }

        for index in items.indices {
            if items[index].matchStatus != "pending" { continue }
            let targetTime = items[index].capturedAt
            if let match = playAtOrBefore(targetTime, in: sortedPlays) {
                items[index].matchStatus = "matched"
                items[index].matchedTrack = match.displayTitle
            }
        }
        save()
    }

    private func playAtOrBefore(_ target: Date, in plays: [RecentlyPlayedItem]) -> RecentlyPlayedItem? {
        var candidate: RecentlyPlayedItem?
        for play in plays {
            if play.playedAt <= target {
                candidate = play
            } else {
                break
            }
        }
        return candidate
    }

    // MARK: - Spotify Recently Played Decoding Skeleton
    func decodeRecentlyPlayed(from data: Data) -> [RecentlyPlayedItem] {
        do {
            let response = try spotifyDecoder().decode(SpotifyRecentlyPlayedResponse.self, from: data)
            return response.items.map { item in
                let artists = item.track.artists.map { $0.name }.joined(separator: ", ")
                return RecentlyPlayedItem(
                    id: UUID(),
                    playedAt: item.playedAt,
                    trackName: item.track.name,
                    artistName: artists,
                    uri: item.track.uri
                )
            }
        } catch {
            lastMessage = "Failed to decode recently played."
            return []
        }
    }

    private func spotifyDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if let date = ISO8601DateFormatter.spotifyFormatter.date(from: rawValue) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(rawValue)")
        }
        return decoder
    }
}

struct RecentlyPlayedItem: Identifiable, Equatable {
    let id: UUID
    let playedAt: Date
    let trackName: String
    let artistName: String
    let uri: String

    var displayTitle: String {
        "\(trackName) • \(artistName)"
    }
}

struct SpotifyRecentlyPlayedResponse: Codable, Equatable {
    let items: [SpotifyRecentlyPlayedItem]
}

struct SpotifyRecentlyPlayedItem: Codable, Equatable {
    let track: SpotifyTrack
    let playedAt: Date

    enum CodingKeys: String, CodingKey {
        case track
        case playedAt = "played_at"
    }
}

struct SpotifyTrack: Codable, Equatable {
    let name: String
    let uri: String
    let artists: [SpotifyArtist]
}

struct SpotifyArtist: Codable, Equatable {
    let name: String
}

extension ISO8601DateFormatter {
    static let spotifyFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let queueFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
