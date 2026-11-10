import Foundation

/// Yönetici izni gerektiren bakım işlemleri. Komutlar sabittir; kullanıcı girdisi içermez.
enum MaintenanceAction: String, CaseIterable, Identifiable, Sendable {
    case optimize, purge, release, releaseDeep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .optimize: return "Tek Tıkla Optimize"
        case .purge: return "Önbelleği Temizle"
        case .release: return "Belleği Boşalt"
        case .releaseDeep: return "Derin Boşaltma"
        }
    }

    var icon: String {
        switch self {
        case .optimize: return "wand.and.stars"
        case .purge: return "externaldrive.badge.xmark"
        case .release: return "arrow.down.right.and.arrow.up.left"
        case .releaseDeep: return "arrow.down.to.line.compact"
        }
    }

    var explanation: String {
        switch self {
        case .optimize:
            return "Önbelleği temizler ve ardından uygulamalardan kullanmadıkları belleği bırakmalarını ister. Tek şifre sorar."
        case .purge:
            return "Disk önbelleğini (son açılan dosyaların RAM'deki kopyaları) boşaltır. Büyük bir uygulama veya oyun açmadan önce işe yarar."
        case .release:
            return "Sisteme 4 saniyeliğine yapay bir \"bellek uyarısı\" verir. Tarayıcılar ve diğer uygulamalar önbelleklerini bırakır; macOS boştaki belleği sıkıştırır."
        case .releaseDeep:
            return "Aynı sinyali \"kritik\" seviyede verir. Uygulamalar daha agresif boşaltır; ardından kısa bir yavaşlama olabilir."
        }
    }

    /// `do shell script` ile yönetici olarak çalıştırılan sabit komut
    fileprivate var command: String {
        switch self {
        case .purge: return "/usr/sbin/purge"
        case .release: return "/usr/bin/memory_pressure -S -l warn -s 4"
        case .releaseDeep: return "/usr/bin/memory_pressure -S -l critical -s 4"
        case .optimize: return "/usr/sbin/purge; /usr/bin/memory_pressure -S -l warn -s 4"
        }
    }
}

struct MaintenanceResult: Identifiable, Sendable {
    let id = UUID()
    let action: MaintenanceAction
    let date: Date
    let before: SystemMemorySnapshot
    let after: SystemMemorySnapshot
    let error: String?

    var freedFree: Int64 { Int64(after.free) - Int64(before.free) }
    var usedDelta: Int64 { Int64(after.used) - Int64(before.used) }
    var cacheDelta: Int64 { Int64(after.cached) - Int64(before.cached) }
}

enum PrivilegedRunner {
    /// macOS'un standart yönetici şifresi penceresini gösterir. Şifre MemScope'a hiç gelmez.
    static func run(_ action: MaintenanceAction) async -> String? {
        await Task.detached(priority: .userInitiated) { () -> String? in
            let script = "do shell script \"\(action.command)\" with administrator privileges with prompt \"MemScope bellek bakımı yapmak için izin istiyor.\""
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            let err = Pipe()
            task.standardError = err
            task.standardOutput = FileHandle.nullDevice
            do { try task.run() } catch { return error.localizedDescription }
            task.waitUntilExit()
            if task.terminationStatus == 0 { return nil }
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if msg.contains("-128") { return "İptal edildi." }
            return msg.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}
