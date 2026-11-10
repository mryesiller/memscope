import Foundation
import SwiftUI

enum ProcCategory: String, CaseIterable, Identifiable, Sendable {
    case app, background, developer, system, critical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: return "Uygulama"
        case .background: return "Arka Plan"
        case .developer: return "Geliştirici"
        case .system: return "Sistem"
        case .critical: return "Kritik"
        }
    }

    var pluralTitle: String {
        switch self {
        case .app: return "Uygulamalar"
        case .background: return "Arka Plan Araçları"
        case .developer: return "Geliştirici Araçları"
        case .system: return "macOS Servisleri"
        case .critical: return "Kritik Sistem"
        }
    }

    var icon: String {
        switch self {
        case .app: return "app.fill"
        case .background: return "moon.zzz.fill"
        case .developer: return "terminal.fill"
        case .system: return "gearshape.2.fill"
        case .critical: return "lock.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .app: return Color(red: 0.36, green: 0.62, blue: 1.0)
        case .background: return Color(red: 1.0, green: 0.72, blue: 0.30)
        case .developer: return Color(red: 0.40, green: 0.85, blue: 0.62)
        case .system: return Color(red: 0.62, green: 0.60, blue: 0.78)
        case .critical: return Color(red: 1.0, green: 0.42, blue: 0.45)
        }
    }

    /// "Önemli mi?" sorusunun kısa cevabı
    var verdict: String {
        switch self {
        case .app: return "Kapatabilirsiniz"
        case .background: return "Güvenle kapatılabilir"
        case .developer: return "Sizin başlattığınız"
        case .system: return "Kendini yönetir"
        case .critical: return "Dokunmayın"
        }
    }

    var advice: String {
        switch self {
        case .app:
            return "Sizin açtığınız bir uygulama. Şu an kullanmıyorsanız kapatarak belleği geri kazanabilirsiniz. Kaydedilmemiş çalışmalarınızı kaydetmeyi unutmayın."
        case .background:
            return "Bir uygulamanın arka plan yardımcısı (güncelleyici, senkronizasyon, menü çubuğu aracı vb.). Kapatmak güvenlidir; ilgili uygulama gerektiğinde yeniden başlatır."
        case .developer:
            return "Terminalden veya bir geliştirme aracından başlatılmış bir süreç. Çalışan bir işiniz (sunucu, derleme, model) yoksa durdurabilirsiniz."
        case .system:
            return "macOS'un bir parçası. Sistem bunu gerektiğinde kendisi başlatır/durdurur ve bellek sıkışınca kendiliğinden geri verir. Kapatmanıza gerek yok."
        case .critical:
            return "macOS'un çalışması için zorunlu. Kapatılırsa oturum kapanabilir veya Mac yeniden başlayabilir."
        }
    }
}

struct ProcInfo: Identifiable, Hashable, Sendable {
    let pid: pid_t
    let ppid: pid_t
    let uid: uid_t
    let name: String
    let path: String
    let memory: UInt64
    let cpu: Double
    let isFootprint: Bool
    var command: String? = nil
    var id: pid_t { pid }
}

struct AppGroup: Identifiable, Hashable, Sendable {
    let id: String
    var displayName: String
    let bundlePath: String?
    let executablePath: String
    let category: ProcCategory
    let knownTitle: String?
    let summary: String
    let tip: String?
    var processes: [ProcInfo]
    var memory: UInt64
    var cpu: Double
    var appPID: pid_t?
    let ownedByUser: Bool
    var commandHint: String? = nil

    var isSelf: Bool {
        bundlePath == Bundle.main.bundlePath || processes.contains { $0.pid == getpid() }
    }
    var canQuit: Bool { ownedByUser && category != .critical && !isSelf }

    var quitBlockReason: String? {
        if isSelf { return "Bu, MemScope'un kendisi." }
        if category == .critical { return "Kritik sistem süreci — kapatılamaz." }
        if !ownedByUser { return "Sistem (root) hesabına ait; yalnızca yönetici kapatabilir." }
        return nil
    }
}

struct HistoryPoint: Identifiable, Sendable {
    let date: Date
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let swap: UInt64
    var id: Date { date }
}

struct QuitRequest: Identifiable {
    let group: AppGroup
    let force: Bool
    var id: String { group.id + (force ? "-f" : "") }
}

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard, processes, maintenance, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return "Panel"
        case .processes: return "Uygulamalar & Süreçler"
        case .maintenance: return "Bakım & Optimize"
        case .settings: return "Ayarlar"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .processes: return "list.bullet.rectangle.fill"
        case .maintenance: return "wand.and.stars"
        case .settings: return "gearshape.fill"
        }
    }
}

extension UInt64 {
    private static let tr = Locale(identifier: "tr_TR")

    var memString: String {
        let gb = Double(self) / 1_073_741_824
        if gb >= 1 { return String(format: "%.2f GB", locale: Self.tr, gb) }
        let mb = Double(self) / 1_048_576
        return mb >= 10 ? String(format: "%.0f MB", locale: Self.tr, mb) : String(format: "%.1f MB", locale: Self.tr, mb)
    }

    var gb: Double { Double(self) / 1_073_741_824 }
}

extension Double {
    func fmt(_ digits: Int = 1) -> String {
        String(format: "%.\(digits)f", locale: Locale(identifier: "tr_TR"), self)
    }
}
