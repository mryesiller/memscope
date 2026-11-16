import Foundation
import AppKit
import Observation

/// Bir uygulama grubuna şu an uygulanan müdahale. Birden fazla kaynak aynı anda isteyebilir; en ağır olan geçerlidir.
struct Intervention: Identifiable, Hashable {
    let groupID: String
    var name: String
    var sources: [String: RuleAction]     // kaynak → istenen eylem (yalnızca geri alınabilir eylemler)
    var applied: RuleAction?              // gerçekten uygulanan (Uygula modu veya Elle)
    var appliedPIDs: Set<pid_t> = []
    var since: Date
    var id: String { groupID }

    var requested: RuleAction? { sources.values.max() }
}

@MainActor
@Observable
final class RuleEngine {
    static let manualSource = "Elle"
    static let governorSource = "Sistem koruyucu"
    static let memorySource = "Bellek koruyucu"
    static let focusSource = "Odak modu"

    var config: EngineConfig {
        didSet {
            guard config != oldValue else { return }
            save()
            if config.mode != oldValue.mode {
                log(.info, source: "Kural motoru", target: "—", action: nil, detail: "Mod: \(oldValue.mode.title) → \(config.mode.title)")
                if config.mode != .enforce { pendingFullReconcile = true }
            }
        }
    }
    var events: [EngineEvent] = []
    var interventions: [String: Intervention] = [:]
    var overloaded = false
    var memoryAlarm = false
    var focusActive: String?

    // Zamanlayıcı durumu
    @ObservationIgnored private var ruleSince: [String: Date] = [:]        // rule|group → koşulun ilk doğru olduğu an
    @ObservationIgnored private var ruleFalseSince: [String: Date] = [:]
    @ObservationIgnored private var firedOnce: Set<String> = []             // tek seferlik eylemler: rule|group|pid
    @ObservationIgnored private var overloadSince: Date?
    @ObservationIgnored private var recoverSince: Date?
    @ObservationIgnored private var governorSteps: [String: (action: RuleAction, at: Date)] = [:]
    @ObservationIgnored private var lastGovernorStep: Date = .distantPast
    @ObservationIgnored private var memorySince: Date?
    @ObservationIgnored private var memoryRecoverSince: Date?
    @ObservationIgnored private var pendingFullReconcile = false
    @ObservationIgnored private var unsavedEvents = 0
    /// Kullanıcının elle geri aldığı gruplar: bu süre boyunca otomatik kaynaklar dokunmaz
    var snoozed: [String: Date] = [:]

    private static let dir: URL = {
        // MEMSCOPE_DATA_DIR yalnızca testler içindir
        let d = ProcessInfo.processInfo.environment["MEMSCOPE_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MemScope", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private let configURL = RuleEngine.dir.appendingPathComponent("rules.json")
    private let eventsURL = RuleEngine.dir.appendingPathComponent("events.json")
    private let ledgerURL = RuleEngine.dir.appendingPathComponent("interventions.json")

    init() {
        if let data = try? Data(contentsOf: configURL), let c = try? JSONDecoder().decode(EngineConfig.self, from: data) {
            config = c
        } else {
            config = EngineConfig()
        }
        if let data = try? Data(contentsOf: eventsURL), let e = try? JSONDecoder().decode([EngineEvent].self, from: data) {
            events = e
        }
        recoverFromCrash()
    }

    // MARK: - Ana döngü

    func evaluate(groups: [AppGroup], system: SystemMemorySnapshot, now: Date) {
        let byID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frontGroup = frontPID.flatMap { pid in groups.first { $0.processes.contains { $0.pid == pid } } }

        // Kaybolan grupları temizle (uygulama kapandı)
        for id in interventions.keys where byID[id] == nil { interventions[id] = nil }

        let auto = config.mode != .off
        if auto {
            evaluateRules(groups, front: frontGroup, now: now)
            evaluateGovernor(groups, system: system, front: frontGroup, now: now)
            evaluateMemoryGuard(groups, system: system, front: frontGroup, now: now)
            evaluateFocus(groups, front: frontGroup)
        } else {
            clearAutomaticSources()
        }
        reconcile(byID, front: frontGroup)
    }

    // MARK: - Uygunluk

    /// Bir gruba otomatik müdahale edilebilir mi? Değilse nedenini döndürür.
    func protection(for g: AppGroup, front: AppGroup?) -> String? {
        if g.isSelf { return "MemScope'un kendisi" }
        if let until = snoozed[g.id], until > Date() { return "Elle geri aldınız (\(until.formatted(date: .omitted, time: .shortened))'e kadar muaf)" }
        if g.category == .critical { return "Kritik sistem süreci" }
        if g.category == .system { return "macOS servisi" }
        if !g.ownedByUser { return "Sistem hesabına ait" }
        if config.protectForeground, let front, front.id == g.id { return "Şu an öndeki uygulama" }
        if !config.exempt.isEmpty, PatternMatcher.matches(config.exempt.joined(separator: ","), group: g) { return "Koruma listesinde" }
        return nil
    }

    // MARK: - Kurallar

    private func evaluateRules(_ groups: [AppGroup], front: AppGroup?, now: Date) {
        var liveKeys: Set<String> = []
        for rule in config.rules where rule.enabled {
            let source = "Kural: \(rule.name)"
            for g in groups where PatternMatcher.matches(rule.match, group: g) {
                guard protection(for: g, front: front) == nil else {
                    removeSource(source, from: g.id)
                    continue
                }
                let key = "\(rule.id)|\(g.id)"
                liveKeys.insert(key)
                let memOK = rule.condition.memoryAboveMB.map { g.memory > UInt64($0) * 1_048_576 } ?? true
                let cpuOK = rule.condition.cpuAbovePercent.map { g.cpu > $0 } ?? true
                if memOK && cpuOK {
                    ruleFalseSince[key] = nil
                    let since = ruleSince[key] ?? now
                    ruleSince[key] = since
                    guard now.timeIntervalSince(since) >= Double(rule.condition.forSeconds) else { continue }
                    fire(rule.action, source: source, group: g, ruleKey: key,
                         reason: conditionText(rule, g))
                } else {
                    ruleSince[key] = nil
                    if interventions[g.id]?.sources[source] != nil {
                        let fs = ruleFalseSince[key] ?? now
                        ruleFalseSince[key] = fs
                        if now.timeIntervalSince(fs) >= 20 { removeSource(source, from: g.id); ruleFalseSince[key] = nil }
                    }
                }
            }
        }
        // Silinen / kapatılan kuralların kaynaklarını kaldır
        let activeSources = Set(config.rules.filter(\.enabled).map { "Kural: \($0.name)" })
        for (id, iv) in interventions {
            for s in iv.sources.keys where s.hasPrefix("Kural: ") && !activeSources.contains(s) { removeSource(s, from: id) }
        }
        ruleSince = ruleSince.filter { liveKeys.contains($0.key) }
    }

    private func conditionText(_ rule: Rule, _ g: AppGroup) -> String {
        var parts: [String] = []
        if rule.condition.memoryAboveMB != nil { parts.append("bellek \(g.memory.memString)") }
        if rule.condition.cpuAbovePercent != nil { parts.append("CPU %\(Int(g.cpu))") }
        return parts.isEmpty ? "eşleşti" : parts.joined(separator: ", ") + " (\(rule.condition.forSeconds) sn)"
    }

    private func fire(_ action: RuleAction, source: String, group g: AppGroup, ruleKey: String, reason: String) {
        switch action {
        case .notify, .quit:
            let mainPID = g.appPID ?? g.processes.map(\.pid).min() ?? 0
            let onceKey = "\(ruleKey)|\(mainPID)"
            guard !firedOnce.contains(onceKey) else { return }
            firedOnce.insert(onceKey)
            if action == .notify {
                // Bildirim uygulamaya dokunmadığı için Deneme modunda da gönderilir
                Notifier.shared.post(key: onceKey, title: "\(g.displayName): \(reason)", body: "\(source) tetiklendi.")
                log(.applied, source: source, target: g.displayName, action: .notify, detail: reason)
            } else if config.mode == .enforce {
                ProcessControl.quit(g)
                log(.applied, source: source, target: g.displayName, action: .quit, detail: reason)
            } else {
                log(.simulated, source: source, target: g.displayName, action: .quit, detail: reason)
            }
        case .background, .suspend:
            if interventions[g.id]?.sources[source] != action {
                setSource(source, action: action, on: g, reason: reason)
            }
        }
    }

    // MARK: - Sistem koruyucu (CPU)

    private func evaluateGovernor(_ groups: [AppGroup], system: SystemMemorySnapshot, front: AppGroup?, now: Date) {
        let gc = config.governor
        guard gc.enabled else { clearSource(Self.governorSource); overloaded = false; return }
        let load = system.cpuUsage * 100

        if load >= gc.highCPUPercent {
            recoverSince = nil
            let since = overloadSince ?? now
            overloadSince = since
            if !overloaded && now.timeIntervalSince(since) >= Double(gc.sustainSeconds) {
                overloaded = true
                log(.info, source: Self.governorSource, target: "Sistem", action: nil, detail: "CPU %\(Int(load)) — \(gc.sustainSeconds) sn boyunca yüksek")
            }
        } else {
            overloadSince = nil
            if overloaded && load <= gc.recoverCPUPercent {
                let rs = recoverSince ?? now
                recoverSince = rs
                if now.timeIntervalSince(rs) >= Double(gc.recoverSeconds) {
                    overloaded = false
                    recoverSince = nil
                    governorSteps.removeAll()
                    log(.info, source: Self.governorSource, target: "Sistem", action: nil, detail: "CPU normale döndü (%\(Int(load))) — kısıtlamalar geri alınıyor")
                    clearSource(Self.governorSource)
                }
            }
        }

        guard overloaded, now.timeIntervalSince(lastGovernorStep) >= Double(gc.stepCooldownSeconds) else { return }
        let offenders = groups
            .filter { $0.cpu >= gc.minOffenderCPU && protection(for: $0, front: front) == nil }
            .sorted { $0.cpu > $1.cpu }
            .prefix(gc.maxOffenders)
        var stepped = false
        for g in offenders {
            let current = governorSteps[g.id]?.action
            let next: RuleAction?
            switch current {
            case nil: next = .background
            case .background?: next = gc.allowSuspend ? .suspend : nil
            default: next = nil
            }
            guard let next else { continue }
            governorSteps[g.id] = (next, now)
            setSource(Self.governorSource, action: next, on: g, reason: "sistem CPU %\(Int(load)), bu uygulama %\(Int(g.cpu))")
            stepped = true
        }
        if stepped { lastGovernorStep = now }
    }

    // MARK: - Bellek koruyucu

    private func evaluateMemoryGuard(_ groups: [AppGroup], system: SystemMemorySnapshot, front: AppGroup?, now: Date) {
        let mg = config.memoryGuard
        guard mg.enabled else { clearSource(Self.memorySource); memoryAlarm = false; return }
        let threshold = mg.trigger == .warning ? PressureLevel.warning.rawValue : PressureLevel.critical.rawValue

        if system.pressure.rawValue >= threshold {
            memoryRecoverSince = nil
            let since = memorySince ?? now
            memorySince = since
            guard !memoryAlarm, now.timeIntervalSince(since) >= Double(mg.sustainSeconds) else { return }
            memoryAlarm = true
            let targets = groups
                .filter { ($0.category == .app || $0.category == .background || $0.category == .developer)
                    && $0.memory >= UInt64(mg.minMemoryMB) * 1_048_576 && protection(for: $0, front: front) == nil }
                .sorted { $0.memory > $1.memory }
                .prefix(mg.maxTargets)
            let names = targets.map(\.displayName).joined(separator: ", ")
            log(.info, source: Self.memorySource, target: "Sistem", action: nil,
                detail: "Bellek basıncı \(system.pressure.title) — en büyük arka plan uygulamaları: \(names.isEmpty ? "yok" : names)")
            if mg.action == .suspend {
                for g in targets { setSource(Self.memorySource, action: .suspend, on: g, reason: "bellek basıncı \(system.pressure.title), \(g.memory.memString)") }
            } else {
                Notifier.shared.post(key: "memguard", title: "Bellek basıncı: \(system.pressure.title)",
                                     body: names.isEmpty ? "Kapatılabilecek büyük bir arka plan uygulaması yok." : "En büyük arka plan uygulamaları: \(names)")
            }
        } else {
            memorySince = nil
            guard memoryAlarm else { return }
            let rs = memoryRecoverSince ?? now
            memoryRecoverSince = rs
            if now.timeIntervalSince(rs) >= Double(mg.recoverSeconds) {
                memoryAlarm = false
                memoryRecoverSince = nil
                log(.info, source: Self.memorySource, target: "Sistem", action: nil, detail: "Bellek basıncı normale döndü")
                clearSource(Self.memorySource)
            }
        }
    }

    // MARK: - Odak modu

    private func evaluateFocus(_ groups: [AppGroup], front: AppGroup?) {
        let fc = config.focus
        guard fc.enabled, !fc.apps.isEmpty, let front,
              fc.apps.contains(where: { $0 == front.bundlePath || $0.caseInsensitiveCompare(front.displayName) == .orderedSame }) else {
            if focusActive != nil {
                log(.info, source: Self.focusSource, target: focusActive ?? "—", action: nil, detail: "Odak uygulaması önden çekildi — arka plandakiler normale dönüyor")
                focusActive = nil
            }
            clearSource(Self.focusSource)
            return
        }
        if focusActive != front.displayName {
            focusActive = front.displayName
            log(.info, source: Self.focusSource, target: front.displayName, action: nil, detail: "Odak uygulaması önde — diğer uygulamalar arka plana alınıyor")
        }
        for g in groups where (g.category == .app || g.category == .background || g.category == .developer) {
            if g.id == front.id || protection(for: g, front: front) != nil {
                removeSource(Self.focusSource, from: g.id)
            } else if interventions[g.id]?.sources[Self.focusSource] == nil {
                setSource(Self.focusSource, action: .background, on: g, reason: "\(front.displayName) önde", quiet: true)
            }
        }
    }

    // MARK: - Elle müdahale

    func applyManual(_ action: RuleAction, to g: AppGroup) {
        guard action.reversible, g.canQuit else { return }
        snoozed[g.id] = nil
        setSource(Self.manualSource, action: action, on: g, reason: "elle")
        pendingFullReconcile = true
    }

    func clearManual(_ g: AppGroup) {
        removeSource(Self.manualSource, from: g.id)
        pendingFullReconcile = true
    }

    /// Bir gruptaki tüm müdahaleleri kaldırır ve 10 dakika boyunca otomatik kurallardan muaf tutar.
    func release(groupID: String) {
        guard let iv = interventions[groupID] else { return }
        for s in iv.sources.keys { removeSource(s, from: groupID) }
        governorSteps[groupID] = nil
        snoozed[groupID] = Date().addingTimeInterval(600)
        log(.info, source: Self.manualSource, target: iv.name, action: nil, detail: "geri alındı — 10 dakika otomatik kurallardan muaf")
    }

    /// Tüm müdahaleleri (elle olanlar dahil) geri alır.
    func rollbackAll(reason: String) {
        for id in Array(interventions.keys) {
            if var iv = interventions[id] {
                iv.sources.removeAll()
                interventions[id] = iv
            }
        }
        governorSteps.removeAll()
        overloaded = false
        memoryAlarm = false
        reconcileOnly()
        log(.info, source: "Kural motoru", target: "—", action: nil, detail: "Tüm müdahaleler geri alındı (\(reason))")
    }

    // MARK: - Kaynak yönetimi

    private func setSource(_ source: String, action: RuleAction, on g: AppGroup, reason: String, quiet: Bool = false) {
        var iv = interventions[g.id] ?? Intervention(groupID: g.id, name: g.displayName, sources: [:], applied: nil, since: Date())
        iv.sources[source] = action
        iv.name = g.displayName
        interventions[g.id] = iv
        let real = config.mode == .enforce || source == Self.manualSource
        if !quiet { log(real ? .applied : .simulated, source: source, target: g.displayName, action: action, detail: reason) }
    }

    private func removeSource(_ source: String, from groupID: String) {
        guard var iv = interventions[groupID], let action = iv.sources[source] else { return }
        iv.sources[source] = nil
        interventions[groupID] = iv
        if source == Self.focusSource { return }   // odak modu tek bir özet olay yazar
        let wasReal = config.mode == .enforce || source == Self.manualSource
        log(wasReal ? .rolledBack : .info, source: source, target: iv.name, action: action,
            detail: wasReal ? "geri alındı" : "koşul geçti (deneme)")
    }

    private func clearSource(_ source: String) {
        for id in interventions.keys where interventions[id]?.sources[source] != nil { removeSource(source, from: id) }
    }

    private func clearAutomaticSources() {
        for (id, iv) in interventions {
            for s in iv.sources.keys where s != Self.manualSource { removeSource(s, from: id) }
        }
        governorSteps.removeAll(); overloaded = false; memoryAlarm = false; focusActive = nil
        overloadSince = nil; memorySince = nil
    }

    // MARK: - Uygulama (gerçek süreç değişiklikleri)

    /// İstenen durum ile uygulanan durumu eşitler. Deneme modunda yalnızca "Elle" kaynakları gerçektir.
    private func reconcile(_ byID: [String: AppGroup], front: AppGroup?) {
        var changed = false
        for (id, var iv) in interventions {
            guard let g = byID[id] else { continue }
            let realSources = iv.sources.filter { config.mode == .enforce || $0.key == Self.manualSource }
            var target = realSources.values.max()
            // Öndeki uygulama asla dondurulmaz (elle bile olsa arka plan modu en fazla)
            if target == .suspend, config.protectForeground, front?.id == id { target = .background }

            let ownedPIDs = Set(g.processes.filter { $0.uid == getuid() }.map(\.pid))
            if target != iv.applied || (target != nil && ownedPIDs != iv.appliedPIDs) {
                ProcessControl.apply(target, previous: iv.applied, pids: ownedPIDs, previousPIDs: iv.appliedPIDs)
                iv.applied = target
                iv.appliedPIDs = target == nil ? [] : ownedPIDs
                changed = true
            }
            if iv.sources.isEmpty && iv.applied == nil {
                interventions[id] = nil
            } else {
                interventions[id] = iv
            }
        }
        pendingFullReconcile = false
        if changed { saveLedger() }
    }

    private func reconcileOnly() {
        for (id, var iv) in interventions where iv.applied != nil {
            ProcessControl.apply(nil, previous: iv.applied, pids: [], previousPIDs: iv.appliedPIDs)
            iv.applied = nil
            iv.appliedPIDs = []
            interventions[id] = iv.sources.isEmpty ? nil : iv
        }
        saveLedger()
    }

    // MARK: - Çökme kurtarma

    private struct LedgerEntry: Codable { let pid: pid_t; let action: String }

    private func saveLedger() {
        let entries = interventions.values.flatMap { iv in
            iv.appliedPIDs.map { LedgerEntry(pid: $0, action: iv.applied?.rawValue ?? "") }
        }
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: ledgerURL, options: .atomic) }
    }

    /// MemScope beklenmedik şekilde kapandıysa dondurduğu süreçleri devam ettirir ve arka plan modunu kaldırır.
    private func recoverFromCrash() {
        guard let data = try? Data(contentsOf: ledgerURL),
              let entries = try? JSONDecoder().decode([LedgerEntry].self, from: data), !entries.isEmpty else { return }
        for e in entries { ProcessControl.restore(pid: e.pid) }
        try? FileManager.default.removeItem(at: ledgerURL)
        log(.info, source: "Kural motoru", target: "—", action: nil, detail: "Önceki oturumdan kalan \(entries.count) müdahale geri alındı")
    }

    // MARK: - Olay kaydı ve kalıcılık

    private func log(_ kind: EngineEvent.Kind, source: String, target: String, action: RuleAction?, detail: String) {
        events.insert(EngineEvent(date: Date(), kind: kind, source: source, target: target, action: action, detail: detail), at: 0)
        if events.count > 500 { events.removeLast(events.count - 500) }
        unsavedEvents += 1
        // Gerçek değişiklikler hemen yazılır (çökmede kaybolmasın); bilgi olayları toplu
        if unsavedEvents >= 10 || kind == .applied || kind == .rolledBack { saveEvents() }
    }

    func clearEvents() {
        events.removeAll()
        saveEvents()
    }

    func saveEvents() {
        unsavedEvents = 0
        if let data = try? JSONEncoder().encode(events) { try? data.write(to: eventsURL, options: .atomic) }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(config) { try? data.write(to: configURL, options: .atomic) }
    }

    func shutdown() {
        rollbackAll(reason: "MemScope kapanıyor")
        saveEvents()
        try? FileManager.default.removeItem(at: ledgerURL)
    }
}

// MARK: - Süreç kontrolü

enum ProcessControl {
    /// target: nil → normale döndür; .background → arka plan QoS; .suspend → dondur
    static func apply(_ target: RuleAction?, previous: RuleAction?, pids: Set<pid_t>, previousPIDs: Set<pid_t>) {
        // Artık hedef olmayan PID'leri normale döndür
        for pid in previousPIDs.subtracting(pids) { restore(pid: pid) }
        for pid in pids {
            switch target {
            case .suspend?:
                kill(pid, SIGSTOP)
            case .background?:
                if previous == .suspend { kill(pid, SIGCONT) }
                setpriority(PRIO_DARWIN_PROCESS, id_t(pid), PRIO_DARWIN_BG)
            default:
                restore(pid: pid)
            }
        }
    }

    static func restore(pid: pid_t) {
        kill(pid, SIGCONT)
        setpriority(PRIO_DARWIN_PROCESS, id_t(pid), 0)
    }

    static func quit(_ g: AppGroup) {
        if let pid = g.appPID, let app = NSRunningApplication(processIdentifier: pid) {
            app.terminate()
        } else {
            for p in g.processes where p.uid == getuid() { kill(p.pid, SIGTERM) }
        }
    }
}
