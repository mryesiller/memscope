import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(MemoryStore.self) private var store
    var scrollable = true

    var body: some View {
        if scrollable { ScrollView { content } } else { content }
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: 16) {
                header
                HStack(alignment: .top, spacing: 16) {
                    GaugeCard().frame(width: 290)
                    BreakdownCard()
                    VStack(spacing: 16) { PressureCard(); SwapCard() }.frame(width: 290)
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 16) {
                    HistoryCard()
                    CategoryCard().frame(width: 360)
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 16) {
                    TopAppsCard()
                    SuggestionsCard()
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bellek Paneli").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("\(store.chipName) · \(store.system.total.memString) birleşik bellek · \(store.groups.filter { $0.category == .app }.count) açık uygulama · \(store.groups.reduce(0) { $0 + $1.processes.count }) süreç")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            RefreshControl()
        }
    }
}

// MARK: - Ana gösterge

struct GaugeCard: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        let s = store.system
        let t = Double(max(s.total, 1))
        Card(title: "Kullanılan Bellek", icon: "memorychip.fill", accent: Theme.app) {
            ZStack {
                MemoryRing(segments: [
                    RingSegment(fraction: Double(s.app) / t, color: Theme.app),
                    RingSegment(fraction: Double(s.wired) / t, color: Theme.wired),
                    RingSegment(fraction: Double(s.compressed) / t, color: Theme.compressed),
                    RingSegment(fraction: Double(s.cached) / t, color: Theme.cached.opacity(0.45)),
                ], lineWidth: 20)
                VStack(spacing: 2) {
                    Text("\(Int((s.usedFraction * 100).rounded()))%")
                        .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("\(s.used.gb.fmt(1)) / \(s.total.gb.fmt(0)) GB")
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: 190, height: 190)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            HStack {
                Label("Boş + Önbellek", systemImage: "leaf.fill").foregroundStyle(Theme.cached)
                Spacer()
                Text((s.free + s.cached).memString).monospacedDigit()
            }
            .font(.system(size: 12, weight: .medium))
            Text("Önbellek, gerektiğinde anında boşaltılır — yani aslında kullanılabilir alandır.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
        }
    }
}

// MARK: - Dağılım

struct BreakdownCard: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        let s = store.system
        let t = Double(max(s.total, 1))
        let parts: [(Color, UInt64)] = [(Theme.app, s.app), (Theme.wired, s.wired), (Theme.compressed, s.compressed), (Theme.cached, s.cached), (Theme.free, s.free)]
        Card(title: "Bellek Nereye Gidiyor?", icon: "chart.bar.doc.horizontal.fill", accent: Theme.compressed) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(p.0.gradient)
                            .frame(width: max(2, (geo.size.width - 12) * Double(p.1) / t))
                    }
                }
            }
            .frame(height: 22)

            VStack(spacing: 11) {
                LegendRow(color: Theme.app, title: "Uygulama Belleği", value: s.app.memString,
                          detail: "Açık uygulamaların aktif olarak kullandığı bellek.")
                LegendRow(color: Theme.wired, title: "Kablolu (Wired)", value: s.wired.memString,
                          detail: "macOS çekirdeğinin kilitlediği, boşaltılamayan bellek.")
                LegendRow(color: Theme.compressed, title: "Sıkıştırılmış", value: s.compressed.memString,
                          detail: "Yer açmak için sıkıştırılmış, az kullanılan veriler.")
                LegendRow(color: Theme.cached, title: "Önbellek (Dosyalar)", value: s.cached.memString,
                          detail: "Son açılan dosyaların kopyası. Gerekince anında boşaltılır.")
                LegendRow(color: Color.white.opacity(0.3), title: "Tamamen Boş", value: s.free.memString)
            }
        }
    }
}

// MARK: - Basınç & Swap

struct PressureCard: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        let p = store.system.pressure
        let color = Theme.pressureColor(p)
        Card(title: "Bellek Basıncı", icon: "gauge.with.dots.needle.67percent", accent: color) {
            HStack(alignment: .firstTextBaseline) {
                Text(p.title).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(color)
                Spacer()
                Text("%\(store.system.freePercent) serbest").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
            }
            MeterBar(fraction: 1 - Double(store.system.freePercent) / 100, color: color, height: 8)
            Text(p.explanation).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SwapCard: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        let s = store.system
        let compressionRatio = Double(s.compressed) / Double(max(s.total, 1))
        Card(title: "Swap & Sıkıştırma", icon: "arrow.triangle.2.circlepath", accent: Theme.swap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Swap").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                    Text(s.swapUsed.memString).font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Sıkıştırılmış").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                    Text("%\(Int(compressionRatio * 100))").font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit()
                }
            }
            Text(s.swapUsed > 2 * 1_073_741_824
                 ? "Swap yüksek: RAM yetmediği için veriler SSD'ye yazılıyor. Büyük uygulamaları kapatmak hızı artırır."
                 : "Swap, RAM yetmediğinde diske yazılan bellektir. Düşük kalması iyidir.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Geçmiş grafiği

enum HistoryRange: String, CaseIterable, Identifiable {
    case live = "Canlı", hour = "1 sa", day = "24 sa", week = "7 gün"
    var id: String { rawValue }
    var seconds: TimeInterval { switch self { case .live: return 0; case .hour: return 3600; case .day: return 86400; case .week: return 7 * 86400 } }
}

struct HistoryCard: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage("historyRange") private var range: HistoryRange = .live

    private struct Pt: Identifiable { let date: Date; let series: String; let gb: Double; var id: String { "\(date.timeIntervalSince1970)\(series)" } }

    private var points: [Pt] {
        func expand(_ d: Date, _ app: UInt64, _ wired: UInt64, _ comp: UInt64) -> [Pt] {
            [Pt(date: d, series: "Uygulama", gb: app.gb), Pt(date: d, series: "Kablolu", gb: wired.gb), Pt(date: d, series: "Sıkıştırılmış", gb: comp.gb)]
        }
        if range == .live {
            return store.history.flatMap { expand($0.date, $0.app, $0.wired, $0.compressed) }
        }
        let cutoff = Date().addingTimeInterval(-range.seconds)
        var src = store.longHistory.filter { $0.t >= cutoff }
        // 7 günlük görünümde ~600 noktaya indir
        let step = max(1, src.count / 600)
        if step > 1 { src = stride(from: 0, to: src.count, by: step).map { src[$0] } }
        return src.flatMap { expand($0.t, $0.app, $0.wired, $0.compressed) }
    }

    var body: some View {
        let pts = points
        Card(title: "Bellek Geçmişi", icon: "waveform.path.ecg", accent: Theme.cached) {
            Picker("", selection: $range) {
                ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 250)
        } content: {
            if pts.count < 6 {
                VStack(spacing: 8) {
                    Image(systemName: "hourglass").font(.system(size: 26)).foregroundStyle(Theme.secondaryText)
                    Text("Veri toplanıyor — MemScope açık kaldıkça dakikalık geçmiş dolar (7 güne kadar).")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).frame(height: 220)
            } else {
                Chart(pts) { p in
                    AreaMark(x: .value("Zaman", p.date), y: .value("GB", p.gb), stacking: .standard)
                        .foregroundStyle(by: .value("Tür", p.series))
                        .interpolationMethod(.monotone)
                }
                .chartForegroundStyleScale([
                    "Uygulama": Theme.app.opacity(0.85),
                    "Kablolu": Theme.wired.opacity(0.85),
                    "Sıkıştırılmış": Theme.compressed.opacity(0.85),
                ])
                .chartYScale(domain: 0...max(1, store.system.total.gb))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d)) GB") } }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.04))
                        switch range {
                        case .live: AxisValueLabel(format: .dateTime.hour().minute().second())
                        case .hour, .day: AxisValueLabel(format: .dateTime.hour().minute())
                        case .week: AxisValueLabel(format: .dateTime.weekday(.abbreviated).hour())
                        }
                    }
                }
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 220)
            }
        }
    }
}

// MARK: - Kategori halkası

struct CategoryCard: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        let totals = store.categoryTotals.filter { $0.1 > 0 }
        let sum = totals.reduce(0) { $0 + $1.1 }
        Card(title: "Kim Kullanıyor?", icon: "chart.pie.fill", accent: ProcCategory.background.color) {
            HStack(spacing: 16) {
                Chart(totals, id: \.0) { item in
                    SectorMark(angle: .value("Bellek", Double(item.1)), innerRadius: .ratio(0.62), angularInset: 2)
                        .foregroundStyle(item.0.color.gradient)
                        .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .frame(width: 130, height: 130)
                .overlay {
                    VStack(spacing: 0) {
                        Text(sum.gb.fmt(1)).font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("GB").font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(totals, id: \.0) { cat, bytes in
                        HStack(spacing: 8) {
                            Circle().fill(cat.color).frame(width: 8, height: 8)
                            Text(cat.pluralTitle).font(.system(size: 12))
                            Spacer(minLength: 4)
                            Text(bytes.memString).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                    }
                }
            }
            Text("Sistem ve kritik süreçler macOS'un kendisidir. Tasarruf, mavi (uygulamalar) ve turuncu (arka plan) dilimlerden yapılır.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - En çok kullananlar

struct TopAppsCard: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        let top = Array(store.groups.prefix(8))
        let maxMem = Double(top.first?.memory ?? 1)
        Card(title: "En Çok Bellek Kullananlar", icon: "flame.fill", accent: Theme.wired) {
            Button("Tümünü Gör") { store.section = .processes }
                .buttonStyle(.plain).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.app)
        } content: {
            VStack(spacing: 6) {
                ForEach(top) { g in
                    Button { store.open(g) } label: {
                        HStack(spacing: 10) {
                            GroupIcon(group: g, size: 26)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(g.displayName).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                    if let hint = g.commandHint {
                                        Text(hint).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(ProcCategory.developer.color).lineLimit(1)
                                    }
                                    if g.processes.count > 1 {
                                        Text("×\(g.processes.count)").font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText)
                                    }
                                    Spacer(minLength: 4)
                                    CategoryBadge(category: g.category, compact: true)
                                }
                                MeterBar(fraction: Double(g.memory) / maxMem, color: g.category.color, height: 5)
                            }
                            Text(g.memory.memString).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .monospacedDigit().frame(width: 76, alignment: .trailing)
                        }
                        .padding(.vertical, 4).padding(.horizontal, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HoverRowStyle())
                }
            }
        }
    }
}

// MARK: - Öneriler

struct SuggestionsCard: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        let list = Array(store.suggestions.prefix(6))
        Card(title: "Kapatılabilecekler", icon: "sparkles", accent: ProcCategory.developer.color) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("~\(store.reclaimable.memString)").font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(ProcCategory.developer.color)
                    Text("geri kazanılabilir").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                Text("Kapatılması güvenli uygulama ve arka plan araçları (150 MB üzeri).")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }
            if !store.growing.isEmpty {
                let (g, delta) = store.growing[0]
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(Theme.swap)
                    Text("**\(g.displayName)** son 1 dakikada \(UInt64(delta).memString) arttı")
                        .font(.system(size: 11.5))
                    Spacer()
                }
                .padding(8)
                .background(Theme.swap.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            if list.isEmpty {
                Label("Şu an kapatılması önerilen bir şey yok.", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.pressureColor(.normal))
            }
            VStack(spacing: 4) {
                ForEach(list) { g in
                    HStack(spacing: 10) {
                        GroupIcon(group: g, size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(g.displayName).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                            Text(g.category.verdict).font(.system(size: 10.5)).foregroundStyle(g.category.color)
                        }
                        Spacer()
                        Text(g.memory.memString).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        Button("Kapat") { store.requestQuit(g) }
                            .buttonStyle(.bordered).controlSize(.small)
                        Button { store.open(g) } label: { Image(systemName: "info.circle") }
                            .buttonStyle(.plain).foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}

struct HoverRowStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(configuration.isPressed ? 0.10 : (hover ? 0.05 : 0))))
            .onHover { hover = $0 }
    }
}
