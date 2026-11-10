import SwiftUI
import AppKit
import Observation

@MainActor
@Observable
final class MemoryStore {
    static let shared = MemoryStore()

    var system = SystemMemorySnapshot.empty
    var groups: [AppGroup] = []
    var history: [HistoryPoint] = []
    var groupHistory: [String: [Double]] = [:]
    var lastUpdate = Date()

    var section: AppSection? = .dashboard
    var selectedGroupID: String?
    var quitRequest: QuitRequest?

    // Bakım
    var maintenanceRunning: MaintenanceAction?
    var lastResult: MaintenanceResult?
    var launchItems: [LaunchItem] = []
    var bulkQuitRequest: [AppGroup]?

    // Uzun dönem geçmiş (dakikalık, 7 gün)
    @ObservationIgnored let recorder = HistoryRecorder()
    var longHistory: [StoredPoint] = []

    static let intervalChoices: [TimeInterval] = [1, 2, 5, 10]
    var interval: TimeInterval = UserDefaults.standard.object(forKey: "interval") as? TimeInterval ?? 2 {
        didSet { UserDefaults.standard.set(interval, forKey: "interval"); scheduleTimer() }
    }
    var paused = false {
        didSet { scheduleTimer(); if !paused { refresh() } }
    }
    static let historyLimit = 180        // 6 dakika
    static let groupHistoryLimit = 90    // 3 dakika

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var sampling = false
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]

    let chipName = SystemMemory.chipName

    init() {
        if !Self.intervalChoices.contains(interval) { interval = 2 }
        longHistory = recorder.points
        refresh()
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard !paused else { return }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        guard !sampling else { return }
        sampling = true
        Task {
            let (sys, raw) = await Task.detached(priority: .utility) {
                (SystemMemory.read(), ProcessSampler.sample())
            }.value
            apply(sys, raw)
            sampling = false
        }
    }

    private func apply(_ sys: SystemMemorySnapshot, _ raw: [AppGroup]) {
        var appsByPID: [pid_t: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications { appsByPID[app.processIdentifier] = app }

        groups = raw.map { g in
            var g = g
            let candidates = g.processes.map(\.pid).sorted().filter { appsByPID[$0] != nil }
            if let pid = candidates.first(where: { appsByPID[$0]?.activationPolicy == .regular }) ?? candidates.first,
               let app = appsByPID[pid] {
                g.appPID = pid
                if g.knownTitle == nil, let n = app.localizedName { g.displayName = n }
            }
            return g
        }.sorted(by: Self.stableOrder)

        system = sys
        let now = Date()
        history.append(HistoryPoint(date: now, app: sys.app, wired: sys.wired, compressed: sys.compressed, swap: sys.swapUsed))
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }

        var newHist: [String: [Double]] = [:]
        for g in groups {
            var h = groupHistory[g.id] ?? []
            h.append(Double(g.memory))
            if h.count > Self.groupHistoryLimit { h.removeFirst(h.count - Self.groupHistoryLimit) }
            newHist[g.id] = h
        }
        groupHistory = newHist
        lastUpdate = now

        if recorder.add(sys, at: now) { longHistory = recorder.points }
        Notifier.shared.evaluate(system: sys, growing: growing)
    }

    /// Küçük dalgalanmalarda satırların yer değiştirmemesi için 25 MB'lık kovalara göre sıralar.
    nonisolated static func stableOrder(_ a: AppGroup, _ b: AppGroup) -> Bool {
        let bucket: UInt64 = 25 * 1_048_576
        let ba = a.memory / bucket, bb = b.memory / bucket
        if ba != bb { return ba > bb }
        return a.id < b.id
    }

    // MARK: - Türetilmiş veriler

    var selectedGroup: AppGroup? {
        guard let id = selectedGroupID else { return nil }
        return groups.first { $0.id == id }
    }

    func totals(by category: ProcCategory) -> UInt64 {
        groups.filter { $0.category == category }.reduce(0) { $0 + $1.memory }
    }

    var categoryTotals: [(ProcCategory, UInt64)] {
        ProcCategory.allCases.map { ($0, totals(by: $0)) }
    }

    /// Kapatılması güvenli ve anlamlı miktarda bellek tutan gruplar
    var suggestions: [AppGroup] {
        groups.filter { ($0.category == .app || $0.category == .background) && $0.canQuit && $0.memory > 150 * 1_048_576 }
    }

    var reclaimable: UInt64 { suggestions.reduce(0) { $0 + $1.memory } }

    /// Hafızası son ~1 dakikada belirgin artan gruplar
    var growing: [(AppGroup, Double)] {
        groups.compactMap { g in
            guard let h = groupHistory[g.id], h.count >= 30, let first = h.suffix(30).first, let last = h.last, first > 0 else { return nil }
            let delta = last - first
            return delta > 100 * 1_048_576 ? (g, delta) : nil
        }.sorted { $0.1 > $1.1 }
    }

    func icon(for group: AppGroup) -> NSImage? {
        guard let bp = group.bundlePath else { return nil }
        if let img = iconCache[bp] { return img }
        let img = NSWorkspace.shared.icon(forFile: bp)
        iconCache[bp] = img
        return img
    }

    // MARK: - Eylemler

    func open(_ group: AppGroup) {
        selectedGroupID = group.id
        section = .processes
    }

    func requestQuit(_ group: AppGroup, force: Bool = false) {
        quitRequest = QuitRequest(group: group, force: force)
    }

    func performQuit(_ req: QuitRequest) {
        let g = req.group
        guard g.canQuit else { return }
        if let pid = g.appPID, let app = NSRunningApplication(processIdentifier: pid) {
            _ = req.force ? app.forceTerminate() : app.terminate()
            if req.force {
                // Yardımcı süreçler de kapansın
                for p in g.processes where p.pid != pid { kill(p.pid, SIGKILL) }
            }
        } else {
            for p in g.processes where p.uid == getuid() {
                kill(p.pid, req.force ? SIGKILL : SIGTERM)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.refresh() }
    }

    func quitMany(_ list: [AppGroup]) {
        for g in list where g.canQuit { performQuit(QuitRequest(group: g, force: false)) }
    }

    // MARK: - Bakım

    func runMaintenance(_ action: MaintenanceAction) {
        guard maintenanceRunning == nil else { return }
        maintenanceRunning = action
        Task {
            let before = await Task.detached { SystemMemory.read() }.value
            let error = await PrivilegedRunner.run(action)
            try? await Task.sleep(for: .seconds(2))
            let after = await Task.detached { SystemMemory.read() }.value
            lastResult = MaintenanceResult(action: action, date: Date(), before: before, after: after, error: error)
            maintenanceRunning = nil
            refresh()
        }
    }

    func reloadLaunchItems() {
        Task {
            launchItems = await Task.detached { LaunchItems.scan() }.value
        }
    }

    /// Bir başlangıç öğesinin şu an çalışan süreç grubunu bulur.
    func runningGroup(for item: LaunchItem) -> AppGroup? {
        guard let program = item.program else { return nil }
        return groups.first { g in g.executablePath == program || g.processes.contains { $0.path == program } }
    }

    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func revealPath(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func revealInFinder(_ group: AppGroup) {
        let path = group.bundlePath ?? group.executablePath
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
