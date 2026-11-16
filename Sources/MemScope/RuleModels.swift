import Foundation
import Darwin

// MARK: - Eylemler

/// Kural motorunun uygulayabileceği eylemler, hafiften ağıra sıralı.
enum RuleAction: String, Codable, CaseIterable, Identifiable, Sendable, Comparable {
    case notify, background, suspend, quit

    var id: String { rawValue }
    var level: Int { Self.allCases.firstIndex(of: self)! }
    static func < (a: Self, b: Self) -> Bool { a.level < b.level }

    var title: String {
        switch self {
        case .notify: return "Bildir"
        case .background: return "Arka plana al (E-core)"
        case .suspend: return "Dondur"
        case .quit: return "Kapat"
        }
    }

    var shortTitle: String {
        switch self {
        case .notify: return "Bildirildi"
        case .background: return "E-core"
        case .suspend: return "Donduruldu"
        case .quit: return "Kapatıldı"
        }
    }

    var icon: String {
        switch self {
        case .notify: return "bell.fill"
        case .background: return "tortoise.fill"
        case .suspend: return "pause.circle.fill"
        case .quit: return "xmark.circle.fill"
        }
    }

    var explanation: String {
        switch self {
        case .notify: return "Sadece bildirim gönderir, uygulamaya dokunmaz."
        case .background: return "Uygulamayı düşük öncelikli arka plan moduna alır: verimlilik çekirdeklerinde (E-core) çalışır, disk erişimi yavaşlar. Çalışmaya devam eder; geri alınabilir."
        case .suspend: return "Uygulamayı tamamen dondurur (CPU kullanmaz, macOS belleğini sıkıştırabilir). Koşul geçince otomatik devam ettirilir."
        case .quit: return "Uygulamaya kapanma sinyali gönderir. Geri alınamaz; kaydedilmemiş veri kaybolabilir."
        }
    }

    /// Koşul geçince geri alınabilir mi?
    var reversible: Bool { self == .background || self == .suspend }
}

// MARK: - Kurallar

struct RuleCondition: Codable, Hashable, Sendable {
    var memoryAboveMB: Int? = nil
    var cpuAbovePercent: Double? = nil   // tek çekirdeğin yüzdesi (100 = 1 çekirdek tam dolu)
    var forSeconds: Int = 30

    var isEmpty: Bool { memoryAboveMB == nil && cpuAbovePercent == nil }
}

struct Rule: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var enabled: Bool = true
    /// Virgülle ayrılmış desenler: "Arc, Google Chrome", "*update*", "/opt/homebrew/*"
    var match: String
    var condition = RuleCondition()
    var action: RuleAction = .notify

    var summary: String {
        var parts: [String] = []
        if let m = condition.memoryAboveMB { parts.append(m >= 1024 ? "bellek > \((Double(m) / 1024).fmt(1)) GB" : "bellek > \(m) MB") }
        if let c = condition.cpuAbovePercent { parts.append("CPU > %\(Int(c))") }
        let when = parts.isEmpty ? "görüldüğünde" : parts.joined(separator: " ve ") + " (\(condition.forSeconds) sn boyunca)"
        return "\(match) · \(when) → \(action.title)"
    }
}

// MARK: - Yapılandırma

enum EngineMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, dryRun, enforce
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Kapalı"
        case .dryRun: return "Deneme"
        case .enforce: return "Uygula"
        }
    }
    var explanation: String {
        switch self {
        case .off: return "Kural motoru çalışmıyor. Elle yaptığınız müdahaleler yine de geçerlidir."
        case .dryRun: return "Hiçbir uygulamaya dokunulmaz. MemScope ne yapacağını Olaylar listesine yazar; bir süre izleyip emin olunca Uygula'ya geçin."
        case .enforce: return "Kurallar gerçekten uygulanır. Öndeki uygulama ve sistem süreçleri her zaman korunur; koşul geçince geri alınabilir eylemler otomatik geri alınır."
        }
    }
}

struct GovernorConfig: Codable, Hashable, Sendable {
    var enabled = true
    var highCPUPercent: Double = 85      // tüm makinenin yüzdesi
    var sustainSeconds = 10
    var recoverCPUPercent: Double = 60
    var recoverSeconds = 20
    var minOffenderCPU: Double = 25       // tek çekirdeğin yüzdesi
    var maxOffenders = 3
    var allowSuspend = false              // basamak 2: dondurma
    var stepCooldownSeconds = 15
}

struct MemoryGuardConfig: Codable, Hashable, Sendable {
    enum Trigger: String, Codable, CaseIterable, Identifiable, Sendable {
        case warning, critical
        var id: String { rawValue }
        var title: String { self == .warning ? "Uyarı" : "Kritik" }
    }
    var enabled = true
    var trigger: Trigger = .warning
    var sustainSeconds = 15
    var action: RuleAction = .notify      // notify veya suspend
    var maxTargets = 2
    var minMemoryMB = 500
    var recoverSeconds = 30
}

struct FocusConfig: Codable, Hashable, Sendable {
    var enabled = false
    /// Odak uygulamalarının paket yolları veya adları
    var apps: [String] = []
}

struct EngineConfig: Codable, Hashable, Sendable {
    var mode: EngineMode = .dryRun
    var protectForeground = true
    var exempt: [String] = ["Finder", "Dock", "MemScope", "Terminal", "Warp", "iTerm2", "Ghostty"]
    var governor = GovernorConfig()
    var memoryGuard = MemoryGuardConfig()
    var focus = FocusConfig()
    var rules: [Rule] = EngineConfig.exampleRules

    static let exampleRules: [Rule] = [
        Rule(name: "Tarayıcı çok büyürse haber ver", enabled: true, match: "Arc, Google Chrome, Safari, Firefox, Microsoft Edge",
             condition: RuleCondition(memoryAboveMB: 4096, forSeconds: 60), action: .notify),
        Rule(name: "Arka planda CPU yiyen Electron uygulamaları", enabled: false, match: "Slack, Discord, Spotify, WhatsApp, Grok Bot",
             condition: RuleCondition(cpuAbovePercent: 40, forSeconds: 30), action: .background),
        Rule(name: "Güncelleyicileri kapat", enabled: false, match: "*update*, *Updater*",
             condition: RuleCondition(forSeconds: 5), action: .quit),
    ]
}

// MARK: - Olaylar

struct EngineEvent: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case applied, simulated, rolledBack, skipped, info }
    var id = UUID()
    let date: Date
    let kind: Kind
    let source: String          // "Kural: …", "Sistem koruyucu", "Bellek koruyucu", "Odak modu", "Elle"
    let target: String          // uygulama adı
    let action: RuleAction?
    let detail: String
}

// MARK: - Desen eşleştirme

enum PatternMatcher {
    /// Virgülle ayrılmış desenlerden biri uygulama adı, çalıştırılabilir adı veya yolla eşleşirse true.
    /// Joker (* ?) yoksa: ad için tam eşleşme (büyük/küçük harf duyarsız). "/" içeren desenler yola uygulanır.
    static func matches(_ patterns: String, group: AppGroup) -> Bool {
        let names = [group.displayName, (group.executablePath as NSString).lastPathComponent,
                     group.bundlePath.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? ""]
            .filter { !$0.isEmpty }
        let path = group.bundlePath ?? group.executablePath
        for raw in patterns.split(separator: ",") {
            let p = raw.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { continue }
            if p.contains("/") {
                // Yol deseni: "/opt/homebrew/*" veya tam önek
                if p.contains("*") || p.contains("?") ? fnmatch(p, path, FNM_CASEFOLD) == 0 : path.hasPrefix(p) { return true }
            } else if p.contains("*") || p.contains("?") {
                // Joker yalnızca adlarda aranır (yolda aranırsa ilgisiz sistem süreçleri eşleşir)
                if names.contains(where: { fnmatch(p, $0, FNM_CASEFOLD) == 0 }) { return true }
            } else if names.contains(where: { $0.caseInsensitiveCompare(p) == .orderedSame }) {
                return true
            }
        }
        return false
    }
}
