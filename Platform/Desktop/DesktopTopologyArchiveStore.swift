import Foundation

/// Persists `TopologyLayoutArchive` as JSON in UserDefaults under `com.katikati.desktop.topologyArchive`.
@MainActor
final class DesktopTopologyArchiveStore {
    private let defaults: UserDefaults
    private let key: String
    private(set) var archive: TopologyLayoutArchive

    init(
        defaults: UserDefaults = .standard,
        key: String = DesktopTopologyConfig.archiveKey
    ) {
        self.defaults = defaults
        self.key = key
        if let raw = defaults.string(forKey: key), let decoded = Self.decode(raw) {
            archive = decoded
        } else {
            archive = TopologyLayoutArchive()
        }
    }

    func entry(forSignature signature: String) -> TopologyArchiveEntry? {
        archive.entry(forSignature: signature)
    }

    func placements(forSignature signature: String) -> [String: TopologyWidgetPlacement] {
        archive.entry(forSignature: signature)?.placements ?? [:]
    }

    func bestEntry(matching displays: [TopologyDisplay]) -> TopologyArchiveEntry? {
        guard !archive.entries.isEmpty, !displays.isEmpty else { return nil }
        return DisplayTopologySimilarity.bestEntry(in: archive, for: displays)
    }

    @discardableResult
    func record(
        signature: String,
        displays: [TopologyDisplay],
        placements: [String: TopologyWidgetPlacement],
        at date: Date = Date()
    ) -> TopologyArchiveEntry {
        let entry = TopologyArchiveEntry(
            signature: signature,
            displays: displays,
            placements: placements,
            updatedAt: date
        )
        archive = archive.recording(entry)
        persist()
        return entry
    }

    func reset() {
        archive = TopologyLayoutArchive()
        defaults.removeObject(forKey: key)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(archive),
              let raw = String(data: data, encoding: .utf8)
        else { return }
        defaults.set(raw, forKey: key)
    }

    nonisolated static func decode(_ raw: String) -> TopologyLayoutArchive? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TopologyLayoutArchive.self, from: data)
    }
}
