import Foundation
import UserNotifications

/// Bellek basıncı, swap ve hızlı büyüme için bildirimler. Her tür için bekleme süresi uygular.
@MainActor
final class Notifier {
    static let shared = Notifier()

    enum Key: String { case pressure, swap, growth }
    static let pressureKey = "notify.pressure"
    static let swapKey = "notify.swap"
    static let growthKey = "notify.growth"

    private var lastSent: [String: Date] = [:]
    private var lastPressure: PressureLevel = .normal
    private let cooldown: TimeInterval = 15 * 60

    private var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    init() {
        UserDefaults.standard.register(defaults: [Self.pressureKey: true, Self.swapKey: true, Self.growthKey: false])
    }

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func evaluate(system: SystemMemorySnapshot, growing: [(AppGroup, Double)]) {
        guard available else { return }
        let d = UserDefaults.standard

        if d.bool(forKey: Self.pressureKey), system.pressure.rawValue > lastPressure.rawValue, system.pressure != .normal {
            send(key: "pressure-\(system.pressure.rawValue)",
                 title: "Bellek basıncı: \(system.pressure.title)",
                 body: system.pressure.explanation)
        }
        lastPressure = system.pressure

        if d.bool(forKey: Self.swapKey), system.swapUsed > 4 * 1_073_741_824 {
            send(key: "swap", title: "Swap kullanımı yüksek (\(system.swapUsed.memString))",
                 body: "RAM yetmediği için veriler diske yazılıyor. MemScope'ta kapatılabilecek uygulamalara göz atın.")
        }

        if d.bool(forKey: Self.growthKey), let (g, delta) = growing.first, delta > 500 * 1_048_576 {
            send(key: "growth-\(g.id)", title: "\(g.displayName) hızla büyüyor",
                 body: "Son dakikada \(UInt64(delta).memString) arttı. Bellek sızıntısı olabilir.")
        }
    }

    private func send(key: String, title: String, body: String) {
        if let last = lastSent[key], Date().timeIntervalSince(last) < cooldown { return }
        lastSent[key] = Date()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key + UUID().uuidString, content: content, trigger: nil))
    }
}
