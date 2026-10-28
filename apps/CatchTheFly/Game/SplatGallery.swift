import Foundation
import Combine

/// One caught fly, kept for the splat gallery. `seed` draws the same splat every time.
struct SplatRecord: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var date: Date
    /// Seconds from the previous catch (or the round start) to this one.
    var catchTime: Double
    /// Which fly of its round (1, 2 or 3).
    var flyNumber: Int
    var roundNumber: Int
    var seed: Int
}

/// The last 30 splats, newest first, kept in UserDefaults as JSON. Main actor only.
@MainActor
final class SplatGallery: ObservableObject {
    static let shared = SplatGallery()
    static let key = "CatchTheFly.splatGallery"
    static let limit = 30

    @Published private(set) var records: [SplatRecord]

    private init() {
        records = SplatGallery.load()
    }

    func add(catchTime: Double, flyNumber: Int, roundNumber: Int) {
        let time = (catchTime.isFinite && catchTime >= 0) ? catchTime : 0
        let record = SplatRecord(id: UUID(), date: Date(), catchTime: time,
                                 flyNumber: max(1, flyNumber), roundNumber: max(1, roundNumber),
                                 seed: Int.random(in: 1...999_999))
        records.insert(record, at: 0)
        if records.count > SplatGallery.limit {
            records.removeLast(records.count - SplatGallery.limit)
        }
        save()
    }

    func clear() {
        records.removeAll()
        UserDefaults.standard.removeObject(forKey: SplatGallery.key)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: SplatGallery.key)
    }

    /// Anything unreadable gives an empty gallery rather than a crash.
    private static func load() -> [SplatRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([SplatRecord].self, from: data) else {
            return []
        }
        // drawSplat turns the seed into a UInt64, so keep it positive.
        let clean = list.filter { $0.seed > 0 && $0.catchTime.isFinite }
        return Array(clean.prefix(limit))
    }
}
