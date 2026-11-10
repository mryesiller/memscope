import Foundation
import Darwin

/// Tüm süreçleri okur, bellek kullanımını hesaplar ve uygulamalara göre gruplar.
enum ProcessSampler {
    private struct RawProc {
        let pid: pid_t, ppid: pid_t, uid: uid_t
        let rss: UInt64, cpu: Double, path: String
    }

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private static let responsibleFn: ResponsibleFn? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let sym = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    static func sample() -> [AppGroup] {
        let raws = listProcesses()
        let myUID = getuid()
        var pathByPid: [pid_t: String] = [:]
        for r in raws { pathByPid[r.pid] = r.path }

        struct Bucket { var bundle: String?; var procs: [ProcInfo] = [] }
        var buckets: [String: Bucket] = [:]

        for r in raws {
            var mem = r.rss
            var isFootprint = false
            if let fp = footprint(of: r.pid) { mem = fp; isFootprint = true }
            let wantsArgs = r.uid == myUID && !r.path.hasPrefix("/System/") && !r.path.hasPrefix("/usr/libexec/") && !r.path.contains(".app/")
            let info = ProcInfo(pid: r.pid, ppid: r.ppid, uid: r.uid,
                                name: (r.path as NSString).lastPathComponent,
                                path: r.path, memory: mem, cpu: r.cpu, isFootprint: isFootprint,
                                command: wantsArgs ? commandLine(of: r.pid) : nil)

            var key = r.path
            var bundle: String? = nil
            if let b = bundlePath(of: r.path) {
                key = b; bundle = b
            } else if r.path.contains(".xpc/"),
                      let resp = responsibleFn?(r.pid), resp > 0, resp != r.pid,
                      let rp = pathByPid[resp], let b = bundlePath(of: rp) {
                // Ör. Safari'nin WebContent süreçleri → Safari grubuna
                key = b; bundle = b
            }
            buckets[key, default: Bucket(bundle: bundle)].procs.append(info)
        }

        return buckets.map { key, bucket in
            let procs = bucket.procs.sorted { $0.memory > $1.memory }
            let execPath: String
            let name: String
            if let b = bucket.bundle {
                let main = procs.filter { $0.path.hasPrefix(b + "/Contents/MacOS/") }.min { $0.pid < $1.pid }
                execPath = main?.path ?? procs.first?.path ?? key
                name = ((b as NSString).lastPathComponent as NSString).deletingPathExtension
            } else {
                execPath = key
                name = (key as NSString).lastPathComponent
            }
            let c = ProcessKnowledge.classify(name: name, execPath: execPath, bundle: bucket.bundle)
            return AppGroup(
                id: key,
                displayName: c.title ?? name,
                bundlePath: bucket.bundle,
                executablePath: execPath,
                category: c.category,
                knownTitle: c.title,
                summary: c.summary,
                tip: c.tip,
                processes: procs,
                memory: procs.reduce(0) { $0 + $1.memory },
                cpu: procs.reduce(0) { $0 + $1.cpu },
                appPID: nil,
                ownedByUser: procs.allSatisfy { $0.uid == myUID },
                commandHint: bucket.bundle == nil ? procs.lazy.filter { $0.command != nil }.compactMap { scriptHint(pid: $0.pid) }.first : nil
            )
        }
    }

    // MARK: - Komut satırı

    private static var argsCache: [pid_t: [String]] = [:]

    static func commandLine(of pid: pid_t) -> String? {
        let a = arguments(of: pid)
        return a.isEmpty ? nil : a.joined(separator: " ")
    }

    /// KERN_PROCARGS2 ile sürecin argümanlarını okur (yalnızca kendi süreçlerimiz). PID başına önbelleğe alınır.
    static func arguments(of pid: pid_t) -> [String] {
        if let c = argsCache[pid] { return c }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        var args: [String] = []
        if sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 {
            var buf = [UInt8](repeating: 0, count: size)
            if sysctl(&mib, 3, &buf, &size, nil, 0) == 0 {
                let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
                var i = 4
                while i < size && buf[i] != 0 { i += 1 }       // exec yolu
                while i < size && buf[i] == 0 { i += 1 }       // dolgu
                while args.count < argc && i < size {
                    let start = i
                    while i < size && buf[i] != 0 { i += 1 }
                    args.append(String(decoding: buf[start..<i], as: UTF8.self))
                    i += 1
                }
            }
        }
        if argsCache.count > 4000 { argsCache.removeAll() }
        argsCache[pid] = args
        return args
    }

    /// ["python3", "-u", "/yol/server.py"] → "server.py";  ["python", "-m", "http.server"] → "http.server"
    static func scriptHint(pid: pid_t) -> String? {
        let args = Array(arguments(of: pid).dropFirst())
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "-m", i + 1 < args.count { return String(args[i + 1].prefix(32)) }
            if a == "-c" || a == "-e" { return "satır içi kod" }
            if a.hasPrefix("-") { i += 1; continue }
            // UUID gibi anlamsız argümanları atla
            if a.count >= 32, a.filter({ $0 == "-" }).count == 4 { i += 1; continue }
            let name = (a as NSString).lastPathComponent
            return name.isEmpty ? nil : String(name.prefix(32))
        }
        return nil
    }

    /// Outermost ".app" paketini döndürür: /Applications/X.app/Contents/Frameworks/Y Helper.app/... → /Applications/X.app
    static func bundlePath(of path: String) -> String? {
        if let r = path.range(of: ".app/") { return String(path[..<r.lowerBound]) + ".app" }
        if path.hasSuffix(".app") { return path }
        return nil
    }

    /// Activity Monitor'ün "Bellek" sütunundaki değer (phys_footprint). Yalnızca kendi kullanıcımızın süreçleri için okunabilir.
    private static func footprint(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return r == 0 ? info.ri_phys_footprint : nil
    }

    /// `ps` root süreçlerinin RSS değerini de görebildiği için ana kaynak olarak kullanılıyor.
    private static func listProcesses() -> [RawProc] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axww", "-o", "pid=,ppid=,uid=,rss=,%cpu=,comm="]
        task.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let psPID = task.processIdentifier
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var result: [RawProc] = []
        result.reserveCapacity(800)
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
            guard parts.count == 6,
                  let pid = Int32(parts[0]), let ppid = Int32(parts[1]),
                  let uid = UInt32(parts[2]), let rss = UInt64(parts[3]),
                  let cpu = Double(parts[4]) else { continue }
            if pid <= 0 || pid == psPID { continue }
            result.append(RawProc(pid: pid, ppid: ppid, uid: uid, rss: rss * 1024, cpu: cpu, path: String(parts[5])))
        }
        return result
    }
}
