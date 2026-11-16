import SwiftUI

struct RulesView: View {
    @Environment(MemoryStore.self) private var store
    var fixedWidth: CGFloat? = nil
    @State private var editing: Rule?

    var body: some View {
        WidthReader(fixedWidth: fixedWidth) { w in content(width: w - 48) }
            .sheet(item: $editing) { rule in
                RuleEditor(rule: rule) { saved in
                    var rules = store.engine.config.rules
                    if let i = rules.firstIndex(where: { $0.id == saved.id }) { rules[i] = saved } else { rules.append(saved) }
                    store.engine.config.rules = rules
                }
                .environment(store)
            }
    }

    private func content(width: CGFloat) -> some View {
        let wide = width >= 960
        return VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Kurallar & Koruma",
                       subtitle: "Arka plan uygulamaları sistemi zorladığında MemScope devreye girer; kullandığınız uygulamaya dokunmaz.") {
                RefreshControl()
            }
            ModeCard()
            ActiveInterventionsCard()
            if wide {
                HStack(alignment: .top, spacing: 16) {
                    GovernorCard()
                    VStack(spacing: 16) { MemoryGuardCard(); FocusCard() }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                GovernorCard()
                MemoryGuardCard()
                FocusCard()
            }
            RuleListCard(editing: $editing)
            EventsCard()
        }
        .padding(24)
    }
}

// MARK: - Mod

struct ModeCard: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        @Bindable var engine = store.engine
        let mode = engine.config.mode
        let color: Color = mode == .enforce ? Theme.pressureColor(.normal) : (mode == .dryRun ? Theme.wired : Theme.secondaryText)
        Card(title: "Çalışma Modu", icon: "dial.medium.fill", accent: color) {
            HStack(alignment: .center, spacing: 16) {
                Picker("", selection: $engine.config.mode) {
                    ForEach(EngineMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260)
                Text(mode.explanation).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().opacity(0.3)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { foregroundToggle; exemptField }
                VStack(alignment: .leading, spacing: 10) { foregroundToggle; exemptField }
            }
            Label("Hiçbir zaman dokunulmayanlar: macOS servisleri, kritik süreçler, sistem hesabına ait süreçler ve MemScope'un kendisi.",
                  systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
        }
    }

    private var foregroundToggle: some View {
        @Bindable var engine = store.engine
        return Toggle("Öndeki uygulamayı koru", isOn: $engine.config.protectForeground).toggleStyle(.switch).fixedSize()
    }

    private var exemptField: some View {
        @Bindable var engine = store.engine
        let binding = Binding<String>(
            get: { engine.config.exempt.joined(separator: ", ") },
            set: { engine.config.exempt = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })
        return HStack(spacing: 8) {
            Text("Koruma listesi").font(.system(size: 12))
            TextField("Finder, Dock, …", text: binding).textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Etkin müdahaleler

struct ActiveInterventionsCard: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        let engine = store.engine
        let list = engine.interventions.values.sorted { $0.since > $1.since }
        Card(title: "Şu An Etkin", icon: "bolt.shield.fill", accent: Theme.app) {
            if !list.isEmpty {
                Button("Tümünü Geri Al") { engine.rollbackAll(reason: "kullanıcı") }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        } content: {
            if list.isEmpty {
                Label(engine.config.mode == .off ? "Kural motoru kapalı." : "Şu an hiçbir uygulamaya müdahale edilmiyor.",
                      systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.pressureColor(.normal))
            }
            ForEach(list) { iv in
                let group = store.groups.first { $0.id == iv.groupID }
                HStack(spacing: 10) {
                    if let group { GroupIcon(group: group, size: 24) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(iv.name).font(.system(size: 12.5, weight: .semibold))
                        Text(iv.sources.map { "\($0.key): \($0.value.title)" }.sorted().joined(separator: " · "))
                            .font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    if let applied = iv.applied {
                        InterventionBadge(action: applied, simulated: false)
                    } else if let req = iv.requested {
                        InterventionBadge(action: req, simulated: true)
                    }
                    if let group { Text(group.memory.memString).font(.system(size: 11.5, design: .rounded)).monospacedDigit().foregroundStyle(Theme.secondaryText) }
                    Button("Geri Al") { engine.release(groupID: iv.groupID) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help("Müdahaleyi kaldırır ve bu uygulamayı 10 dakika otomatik kurallardan muaf tutar")
                }
                .padding(.vertical, 3)
            }
        }
    }
}

struct InterventionBadge: View {
    let action: RuleAction
    let simulated: Bool

    var body: some View {
        let color: Color = action == .suspend ? Theme.swap : (action == .background ? ProcCategory.developer.color : Theme.app)
        HStack(spacing: 4) {
            Image(systemName: action.icon).font(.system(size: 9, weight: .bold))
            Text(simulated ? "\(action.shortTitle) (deneme)" : action.shortTitle).font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .foregroundStyle(simulated ? Theme.secondaryText : color)
        .background((simulated ? Color.white : color).opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(simulated ? Color.white.opacity(0.2) : .clear, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
    }
}

// MARK: - Sistem koruyucu

struct GovernorCard: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        @Bindable var engine = store.engine
        let g = engine.config.governor
        let load = store.system.cpuUsage * 100
        Card(title: "Sistem Koruyucu (CPU)", icon: "cpu.fill", accent: Theme.wired) {
            Toggle("", isOn: $engine.config.governor.enabled).toggleStyle(.switch).labelsHidden()
        } content: {
            Text("Toplam CPU uzun süre yüksek kalırsa, en çok CPU kullanan arka plan uygulamalarını kademeli olarak yavaşlatır; yük düşünce hepsini geri alır.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Şu an CPU").font(.system(size: 11.5))
                    Spacer()
                    Text("%\(Int(load))").font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                    if engine.overloaded {
                        Text("AŞIRI YÜK").font(.system(size: 9.5, weight: .heavy)).foregroundStyle(Theme.swap)
                            .padding(.horizontal, 5).padding(.vertical, 2).background(Theme.swap.opacity(0.15), in: Capsule())
                    }
                }
                ThresholdBar(value: load / 100, high: g.highCPUPercent / 100, low: g.recoverCPUPercent / 100, color: Theme.wired)
            }

            Group {
                NumberRow(title: "Aşırı yük eşiği", value: $engine.config.governor.highCPUPercent, range: 50...100, step: 5, suffix: "%")
                IntRow(title: "… şu kadar sürerse", value: $engine.config.governor.sustainSeconds, range: 3...120, step: 1, suffix: "sn")
                NumberRow(title: "Normale dönüş eşiği", value: $engine.config.governor.recoverCPUPercent, range: 20...95, step: 5, suffix: "%")
                IntRow(title: "… şu kadar sürerse", value: $engine.config.governor.recoverSeconds, range: 5...300, step: 5, suffix: "sn")
                NumberRow(title: "Uygulama en az şu kadar CPU kullanıyorsa", value: $engine.config.governor.minOffenderCPU, range: 5...400, step: 5, suffix: "% çekirdek")
                IntRow(title: "Aynı anda en fazla", value: $engine.config.governor.maxOffenders, range: 1...10, step: 1, suffix: "uygulama")
            }
            Divider().opacity(0.3)
            VStack(alignment: .leading, spacing: 4) {
                Text("Basamaklar").font(.system(size: 11.5, weight: .semibold))
                Label("1 · Arka plana al (E-core) — her zaman", systemImage: "tortoise.fill").font(.system(size: 11.5))
                Toggle(isOn: $engine.config.governor.allowSuspend) {
                    Label("2 · Hâlâ yüksekse dondur", systemImage: "pause.circle.fill").font(.system(size: 11.5))
                }
                .toggleStyle(.checkbox)
            }
        }
        .onChange(of: engine.config.governor.highCPUPercent) { _, v in
            if engine.config.governor.recoverCPUPercent >= v { engine.config.governor.recoverCPUPercent = max(20, v - 10) }
        }
        .onChange(of: engine.config.governor.recoverCPUPercent) { _, v in
            if v >= engine.config.governor.highCPUPercent { engine.config.governor.recoverCPUPercent = engine.config.governor.highCPUPercent - 5 }
        }
    }
}

struct ThresholdBar: View {
    let value: Double, high: Double, low: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule().fill((value >= high ? Theme.swap : color).gradient).frame(width: max(6, geo.size.width * min(1, value)))
                Rectangle().fill(Theme.swap).frame(width: 2).offset(x: geo.size.width * high - 1)
                Rectangle().fill(Theme.pressureColor(.normal)).frame(width: 2).offset(x: geo.size.width * low - 1)
            }
        }
        .frame(height: 8)
    }
}

struct NumberRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String

    var body: some View {
        HStack {
            Text(title).font(.system(size: 11.5))
            Spacer(minLength: 8)
            Text("\(Int(value)) \(suffix)").font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
            Stepper("", value: $value, in: range, step: step).labelsHidden()
        }
    }
}

struct IntRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let suffix: String

    var body: some View {
        HStack {
            Text(title).font(.system(size: 11.5))
            Spacer(minLength: 8)
            Text("\(value) \(suffix)").font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
            Stepper("", value: $value, in: range, step: step).labelsHidden()
        }
    }
}

// MARK: - Bellek koruyucu

struct MemoryGuardCard: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        @Bindable var engine = store.engine
        Card(title: "Bellek Koruyucu", icon: "memorychip.fill", accent: Theme.compressed) {
            Toggle("", isOn: $engine.config.memoryGuard.enabled).toggleStyle(.switch).labelsHidden()
        } content: {
            Text("Bellek basıncı yükselip öyle kalırsa en büyük arka plan uygulamalarını bildirir veya dondurur. Dondurulan uygulamanın belleğini macOS sıkıştırıp öndeki uygulamaya verebilir.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Tetikleyici").font(.system(size: 11.5))
                Spacer()
                Picker("", selection: $engine.config.memoryGuard.trigger) {
                    ForEach(MemoryGuardConfig.Trigger.allCases) { Text("Basınç: \($0.title)").tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            HStack {
                Text("Eylem").font(.system(size: 11.5))
                Spacer()
                Picker("", selection: $engine.config.memoryGuard.action) {
                    Text("Bildir").tag(RuleAction.notify)
                    Text("En büyükleri dondur").tag(RuleAction.suspend)
                }
                .labelsHidden().fixedSize()
            }
            if engine.config.memoryGuard.action == .suspend {
                IntRow(title: "En fazla", value: $engine.config.memoryGuard.maxTargets, range: 1...6, step: 1, suffix: "uygulama")
                IntRow(title: "En az bellek", value: $engine.config.memoryGuard.minMemoryMB, range: 100...8000, step: 100, suffix: "MB")
            }
            HStack(spacing: 6) {
                Circle().fill(engine.memoryAlarm ? Theme.swap : Theme.pressureColor(.normal)).frame(width: 7, height: 7)
                Text(engine.memoryAlarm ? "Etkin — bellek basıncı yüksek" : "Bekliyor · şu an basınç \(store.system.pressure.title)")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

// MARK: - Odak modu

struct FocusCard: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        @Bindable var engine = store.engine
        let candidates = store.groups.filter { $0.category == .app && $0.appPID != nil && !$0.isSelf }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        Card(title: "Odak Modu", icon: "scope", accent: ProcCategory.developer.color) {
            Toggle("", isOn: $engine.config.focus.enabled).toggleStyle(.switch).labelsHidden()
        } content: {
            Text("Seçtiğiniz uygulama (oyun, Blender, Xcode…) öndeyken diğer tüm uygulamalar arka plana (E-core) alınır; önden çekilince hemen normale döner.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            FlowList(items: engine.config.focus.apps) { app in
                HStack(spacing: 4) {
                    Text(((app as NSString).lastPathComponent as NSString).deletingPathExtension).font(.system(size: 11.5))
                    Button { engine.config.focus.apps.removeAll { $0 == app } } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(ProcCategory.developer.color.opacity(0.12), in: Capsule())
            }
            Menu {
                ForEach(candidates) { g in
                    Button(g.displayName) {
                        let key = g.bundlePath ?? g.displayName
                        if !engine.config.focus.apps.contains(key) { engine.config.focus.apps.append(key) }
                    }
                }
            } label: { Label("Uygulama ekle", systemImage: "plus") }
            .fixedSize()
            if let active = engine.focusActive {
                Label("\(active) önde — odak modu etkin", systemImage: "scope").font(.system(size: 11)).foregroundStyle(ProcCategory.developer.color)
            }
        }
    }
}

/// Basit sarmalayan yatay liste
struct FlowList<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        if !items.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { content($0) }
            }
        }
    }
}

// MARK: - Kural listesi

struct RuleListCard: View {
    @Environment(MemoryStore.self) private var store
    @Binding var editing: Rule?

    var body: some View {
        @Bindable var engine = store.engine
        Card(title: "Kurallar", icon: "list.bullet.rectangle.portrait.fill", accent: Theme.cached) {
            Button { editing = Rule(name: "Yeni kural", match: "") } label: { Label("Yeni Kural", systemImage: "plus") }
                .buttonStyle(.borderedProminent).controlSize(.small)
        } content: {
            Text("Belirli uygulamalar için koşul ve eylem tanımlayın. Örnek: \"Slack 30 saniye boyunca %40 CPU'yu geçerse arka plana al\".")
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
            if engine.config.rules.isEmpty {
                Text("Henüz kural yok.").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
            ForEach($engine.config.rules) { $rule in
                let allMatched = store.groups.filter { PatternMatcher.matches(rule.match, group: $0) }
                let matched = allMatched.filter { engine.protection(for: $0, front: nil) == nil }
                let protectedCount = allMatched.count - matched.count
                HStack(spacing: 10) {
                    Toggle("", isOn: $rule.enabled).toggleStyle(.switch).labelsHidden().controlSize(.small)
                    Image(systemName: rule.action.icon).foregroundStyle(rule.enabled ? Theme.cached : Theme.secondaryText)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.name).font(.system(size: 12.5, weight: .semibold))
                        Text(rule.summary).font(.system(size: 11)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(matched.isEmpty ? "eşleşen yok" : "\(matched.count) eşleşme")
                            .font(.system(size: 10.5)).foregroundStyle(matched.isEmpty ? Theme.secondaryText : Theme.cached)
                        if protectedCount > 0 {
                            Text("+\(protectedCount) korumalı").font(.system(size: 9.5)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .help(allMatched.map { g in engine.protection(for: g, front: nil).map { "\(g.displayName) (korumalı: \($0))" } ?? g.displayName }.joined(separator: "\n"))
                    Button { editing = rule } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
                    Button(role: .destructive) { engine.config.rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
                .opacity(rule.enabled ? 1 : 0.6)
                Divider().opacity(0.25)
            }
        }
    }
}

struct RuleEditor: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var rule: Rule
    let onSave: (Rule) -> Void

    var body: some View {
        let matched = store.groups.filter { PatternMatcher.matches(rule.match, group: $0) && store.engine.protection(for: $0, front: nil) == nil }
        VStack(alignment: .leading, spacing: 14) {
            Text("Kural").font(.system(size: 20, weight: .bold, design: .rounded))
            Form {
                TextField("Ad", text: $rule.name)
                HStack {
                    TextField("Uygulamalar", text: $rule.match, prompt: Text("Arc, Slack, *update*, /opt/homebrew/*"))
                    Menu {
                        ForEach(store.groups.filter { $0.canQuit }.prefix(40)) { g in
                            Button(g.displayName) {
                                rule.match = rule.match.trimmingCharacters(in: .whitespaces).isEmpty ? g.displayName : rule.match + ", " + g.displayName
                            }
                        }
                    } label: { Image(systemName: "plus.circle") }
                    .fixedSize()
                }
                Text("Virgülle ayırın. * ve ? joker karakterdir; / ile başlayan yol önekidir.")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)

                Section("Koşul") {
                    Toggle("Bellek şu değeri geçerse", isOn: Binding(
                        get: { rule.condition.memoryAboveMB != nil },
                        set: { rule.condition.memoryAboveMB = $0 ? (rule.condition.memoryAboveMB ?? 2048) : nil }))
                    if rule.condition.memoryAboveMB != nil {
                        Stepper(value: Binding(get: { rule.condition.memoryAboveMB ?? 0 }, set: { rule.condition.memoryAboveMB = $0 }),
                                in: 100...65536, step: 256) {
                            Text("\(rule.condition.memoryAboveMB ?? 0) MB").monospacedDigit()
                        }
                    }
                    Toggle("CPU şu değeri geçerse", isOn: Binding(
                        get: { rule.condition.cpuAbovePercent != nil },
                        set: { rule.condition.cpuAbovePercent = $0 ? (rule.condition.cpuAbovePercent ?? 50) : nil }))
                    if rule.condition.cpuAbovePercent != nil {
                        Stepper(value: Binding(get: { rule.condition.cpuAbovePercent ?? 0 }, set: { rule.condition.cpuAbovePercent = $0 }),
                                in: 5...1200, step: 5) {
                            Text("%\(Int(rule.condition.cpuAbovePercent ?? 0)) (100 = bir çekirdek tam dolu)").monospacedDigit()
                        }
                    }
                    Stepper(value: $rule.condition.forSeconds, in: 0...3600, step: 5) {
                        Text(rule.condition.isEmpty ? "Görüldükten \(rule.condition.forSeconds) sn sonra" : "\(rule.condition.forSeconds) saniye boyunca sürerse").monospacedDigit()
                    }
                }
                Section("Eylem") {
                    Picker("Eylem", selection: $rule.action) {
                        ForEach(RuleAction.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                    Text(rule.action.explanation).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if rule.action == .quit {
                        Label("Kapatma geri alınamaz. Önce Deneme modunda izlemeniz önerilir.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "eye").foregroundStyle(.secondary)
                Text(matched.isEmpty ? "Şu an çalışan eşleşen uygulama yok." :
                        "Şu an eşleşen: " + matched.prefix(6).map { "\($0.displayName) (\($0.memory.memString))" }.joined(separator: ", "))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Kaydet") { onSave(rule); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(rule.name.trimmingCharacters(in: .whitespaces).isEmpty || rule.match.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 640)
    }
}

// MARK: - Olaylar

struct EventsCard: View {
    @Environment(MemoryStore.self) private var store
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tümü", actions = "Eylemler", simulated = "Deneme"
        var id: String { rawValue }
    }

    var body: some View {
        let engine = store.engine
        let events = engine.events.filter {
            switch filter {
            case .all: return true
            case .actions: return $0.kind == .applied || $0.kind == .rolledBack
            case .simulated: return $0.kind == .simulated
            }
        }.prefix(120)
        Card(title: "Olaylar", icon: "clock.arrow.circlepath", accent: Theme.secondaryText) {
            HStack(spacing: 10) {
                Picker("", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                Button("Temizle") { engine.clearEvents() }.buttonStyle(.borderless).font(.system(size: 11.5))
            }
        } content: {
            if events.isEmpty {
                Text(engine.config.mode == .dryRun
                     ? "Henüz olay yok. Deneme modunda MemScope ne yapacağını buraya yazar."
                     : "Henüz olay yok.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
            VStack(spacing: 0) {
                ForEach(Array(events)) { e in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(e.date.formatted(date: .omitted, time: .standard)).font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.secondaryText).frame(width: 64, alignment: .leading)
                        kindBadge(e.kind).frame(width: 82, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                if let a = e.action { Image(systemName: a.icon).font(.system(size: 10)) }
                                Text(e.target).font(.system(size: 12, weight: .medium))
                                if let a = e.action { Text("· \(a.title)").font(.system(size: 11.5)) }
                            }
                            Text("\(e.source) — \(e.detail)").font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5)
                    Divider().opacity(0.2)
                }
            }
        }
    }

    private func kindBadge(_ k: EngineEvent.Kind) -> some View {
        let (text, color): (String, Color) = {
            switch k {
            case .applied: return ("Uygulandı", Theme.pressureColor(.normal))
            case .simulated: return ("Deneme", Theme.wired)
            case .rolledBack: return ("Geri alındı", Theme.app)
            case .skipped: return ("Atlandı", Theme.secondaryText)
            case .info: return ("Bilgi", Theme.secondaryText)
            }
        }()
        return Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.12), in: Capsule())
    }
}
