import Foundation
import Darwin

enum PressureLevel: Int, Sendable {
    case normal = 1, warning = 2, critical = 4

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Uyarı"
        case .critical: return "Kritik"
        }
    }

    var explanation: String {
        switch self {
        case .normal:
            return "Her şey yolunda. RAM'in dolu görünmesi normaldir; macOS boş belleği önbellek olarak kullanır."
        case .warning:
            return "macOS belleği sıkıştırmaya ve diske (swap) yazmaya başladı. Kullanmadığınız büyük uygulamaları kapatmayı düşünün."
        case .critical:
            return "Bellek yetersiz. Sistem yavaşlayabilir; büyük uygulamaları hemen kapatın."
        }
    }
}

/// Activity Monitor'daki "Bellek" sekmesiyle aynı hesaplama mantığı.
struct SystemMemorySnapshot: Sendable {
    var total: UInt64 = 0
    var app: UInt64 = 0          // Uygulama belleği
    var wired: UInt64 = 0        // Kablolu (kilitli) bellek
    var compressed: UInt64 = 0   // Sıkıştırılmış
    var cached: UInt64 = 0       // Dosya önbelleği (anında boşaltılabilir)
    var free: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressure: PressureLevel = .normal
    var freePercent: Int = 100   // kern.memorystatus_level

    var used: UInt64 { app + wired + compressed }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static let empty = SystemMemorySnapshot()
}

enum SystemMemory {
    static func read() -> SystemMemorySnapshot {
        var snap = SystemMemorySnapshot()
        snap.total = ProcessInfo.processInfo.physicalMemory

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let internalPages = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            let external = UInt64(stats.external_page_count)
            snap.app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
            snap.wired = UInt64(stats.wire_count) * page
            snap.compressed = UInt64(stats.compressor_page_count) * page
            snap.cached = (external + purgeable) * page
            let used = snap.app + snap.wired + snap.compressed + snap.cached
            snap.free = snap.total > used ? snap.total - used : 0
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            snap.swapUsed = swap.xsu_used
            snap.swapTotal = swap.xsu_total
        }

        if let lvl = sysctlInt32("kern.memorystatus_vm_pressure_level"), let p = PressureLevel(rawValue: Int(lvl)) {
            snap.pressure = p
        }
        if let freePct = sysctlInt32("kern.memorystatus_level") {
            snap.freePercent = Int(freePct)
        }
        return snap
    }

    static func sysctlInt32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    static var chipName: String { sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon" }
}
