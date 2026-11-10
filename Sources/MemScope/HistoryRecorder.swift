import Foundation

/// Dakikalık ortalamaları ~/Library/Application Support/MemScope/history.json dosyasına yazar (7 gün).
struct StoredPoint: Codable, Identifiable, Sendable {
    let t: Date
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let swap: UInt64
    let pressure: Int
    var id: Date { t }
}

@MainActor
final class HistoryRecorder {
    static let maxPoints = 7 * 24 * 60

    private(set) var points: [StoredPoint] = []
    private var bucketMinute: Int?
    private var acc: (n: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, swap: UInt64, pressure: Int) = (0, 0, 0, 0, 0, 1)
    private var unsaved = 0

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MemScope", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([StoredPoint].self, from: data) {
            let cutoff = Date().addingTimeInterval(-7 * 86400)
            points = decoded.filter { $0.t > cutoff }
        }
    }

    /// Yeni bir örnek ekler; dakika değiştiğinde önceki dakikanın ortalamasını kaydeder. Yeni nokta eklendiyse true döner.
    @discardableResult
    func add(_ s: SystemMemorySnapshot, at date: Date) -> Bool {
        let minute = Int(date.timeIntervalSince1970 / 60)
        var flushed = false
        if let m = bucketMinute, m != minute, acc.n > 0 {
            points.append(StoredPoint(t: Date(timeIntervalSince1970: TimeInterval(m * 60)),
                                      app: acc.app / acc.n, wired: acc.wired / acc.n,
                                      compressed: acc.compressed / acc.n, swap: acc.swap / acc.n,
                                      pressure: acc.pressure))
            if points.count > Self.maxPoints { points.removeFirst(points.count - Self.maxPoints) }
            acc = (0, 0, 0, 0, 0, 1)
            unsaved += 1
            flushed = true
            if unsaved >= 5 { save() }
        }
        bucketMinute = minute
        acc.n += 1
        acc.app += s.app; acc.wired += s.wired; acc.compressed += s.compressed; acc.swap += s.swapUsed
        acc.pressure = max(acc.pressure, s.pressure.rawValue)
        return flushed
    }

    func save() {
        unsaved = 0
        guard let data = try? JSONEncoder().encode(points) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
