import SwiftUI
import Charts

enum SortKey: String, CaseIterable, Identifiable {
    case memory = "Bellek", cpu = "CPU", name = "İsim", count = "Süreç sayısı"
    var id: String { rawValue }
}

struct ProcessesView: View {
    @Environment(MemoryStore.self) private var store
    @State private var search = ""
    @State private var filter: ProcCategory? = nil
    @State private var sort: SortKey = .memory

    private var filtered: [AppGroup] {
        var list = store.groups
        if let filter { list = list.filter { $0.category == filter } }
        if !search.isEmpty {
            let q = search.lowercased()
            list = list.filter {
                $0.displayName.lowercased().contains(q) || $0.executablePath.lowercased().contains(q)
                    || $0.processes.contains { $0.name.lowercased().contains(q) || String($0.pid) == q }
            }
        }
        switch sort {
        case .memory: list.sort(by: MemoryStore.stableOrder)
        case .cpu: list.sort { $0.cpu > $1.cpu }
        case .name: list.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .count: list.sort { $0.processes.count > $1.processes.count }
        }
        return list
    }

    var body: some View {
        @Bindable var store = store
        GeometryReader { geo in
        // Ayrıntı paneli pencereyle birlikte daralır (300–400 pt); liste kalan alanı alır.
        let inspectorWidth = min(400, max(300, geo.size.width * 0.34))
        let listWidth = geo.size.width - inspectorWidth - 40
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                toolbar
                filterChips
                let items = filtered
                let maxMem = Double(items.map(\.memory).max() ?? 1)
                List(items, selection: $store.selectedGroupID) { g in
                    GroupRow(group: g, maxMem: maxMem, compact: listWidth < 640).tag(g.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .padding(.top, 20).padding(.horizontal, 20)
            .frame(maxWidth: .infinity)

            Divider().overlay(Theme.cardStroke)

            Group {
                if let g = store.selectedGroup {
                    InspectorView(group: g)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "cursorarrow.click.2").font(.system(size: 34)).foregroundStyle(Theme.secondaryText)
                        Text("Ne işe yaradığını görmek için\nbir uygulama veya süreç seçin.")
                            .multilineTextAlignment(.center).foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: inspectorWidth)
            .background(Color.black.opacity(0.15))
        }
        }
    }

    /// Geniş: tek satır. Dar: başlık + yenileme üstte, arama + sıralama altta.
    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                titleBlock
                Spacer(minLength: 12)
                RefreshControl().fixedSize()
                searchField.frame(width: 220)
                sortPicker
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    titleBlock
                    Spacer(minLength: 12)
                    RefreshControl().fixedSize()
                }
                HStack(spacing: 10) {
                    searchField.frame(maxWidth: 320)
                    Spacer(minLength: 0)
                    sortPicker
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                titleBlock
                RefreshControl().fixedSize()
                HStack(spacing: 10) { searchField; sortPicker }
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Uygulamalar & Süreçler").font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(1).fixedSize()
            Text("Yardımcı süreçler ait oldukları uygulamanın altında toplanır.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText).lineLimit(1)
        }
    }

    private var sortPicker: some View {
        Picker("Sırala", selection: $sort) {
            ForEach(SortKey.allCases) { Text($0.rawValue).tag($0) }
        }
        .fixedSize()
    }

    private var searchField: some View {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
                TextField("Ara: isim, yol veya PID", text: $search).textFieldStyle(.plain).frame(minWidth: 120)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, title: "Tümü", icon: "square.stack.3d.up.fill", color: .white, total: store.groups.reduce(0) { $0 + $1.memory }, count: store.groups.count)
                ForEach(ProcCategory.allCases) { c in
                    chip(c, title: c.pluralTitle, icon: c.icon, color: c.color, total: store.totals(by: c), count: store.groups.filter { $0.category == c }.count)
                }
            }
        }
    }

    private func chip(_ c: ProcCategory?, title: String, icon: String, color: Color, total: UInt64, count: Int) -> some View {
        let active = filter == c
        return Button { withAnimation(.snappy) { filter = c } } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
                Text(title).font(.system(size: 12, weight: .medium))
                Text("\(count) · \(total.memString)").font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(active ? color.opacity(0.22) : Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(active ? color.opacity(0.6) : Color.clear))
        }
        .buttonStyle(.plain)
    }
}

struct GroupRow: View {
    let group: AppGroup
    let maxMem: Double
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            GroupIcon(group: group, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(group.displayName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let hint = group.commandHint {
                        Text(hint).font(.system(size: 11, design: .monospaced)).foregroundStyle(ProcCategory.developer.color).lineLimit(1)
                    }
                    if group.processes.count > 1 {
                        Text("\(group.processes.count) süreç").font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.white.opacity(0.07), in: Capsule())
                    }
                }
                Text(group.summary).font(.system(size: 11)).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 8)
            CategoryBadge(category: group.category, compact: compact)
            VStack(alignment: .trailing, spacing: 4) {
                Text(group.memory.memString).font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                MeterBar(fraction: Double(group.memory) / maxMem, color: group.category.color, height: 4).frame(width: 80)
            }
            .frame(width: 90)
            Text("\(group.cpu.fmt(1))%").font(.system(size: 11.5, design: .rounded)).monospacedDigit()
                .foregroundStyle(group.cpu > 50 ? Theme.wired : Theme.secondaryText)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }
}

struct InspectorView: View {
    @Environment(MemoryStore.self) private var store
    let group: AppGroup
    var scrollable = true

    var body: some View {
        if scrollable { ScrollView { content } } else { content }
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    GroupIcon(group: group, size: 54)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.displayName).font(.system(size: 19, weight: .bold, design: .rounded)).lineLimit(2)
                        CategoryBadge(category: group.category)
                    }
                }

                HStack(spacing: 10) {
                    stat("Bellek", group.memory.memString, Theme.app)
                    stat("CPU", "\(group.cpu.fmt(1))%", Theme.wired)
                    stat("Süreç", "\(group.processes.count)", Theme.cached)
                }

                section("Ne işe yarar?", icon: "questionmark.circle.fill") {
                    Text(group.summary).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Önemli mi? — \(group.category.verdict)", systemImage: group.category.icon)
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(group.category.color)
                    Text(group.category.advice).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    if let tip = group.tip {
                        Divider().opacity(0.3)
                        Label { Text(tip).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true) }
                            icon: { Image(systemName: "lightbulb.fill").foregroundStyle(.yellow) }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(group.category.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(group.category.color.opacity(0.25)))

                if let hist = store.groupHistory[group.id], hist.count > 1 {
                    section("Bellek geçmişi (son \(hist.count * Int(store.interval)) sn)", icon: "chart.xyaxis.line") {
                        Chart(Array(hist.enumerated()), id: \.offset) { i, v in
                            AreaMark(x: .value("t", i), y: .value("MB", v / 1_048_576))
                                .foregroundStyle(LinearGradient(colors: [group.category.color.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                            LineMark(x: .value("t", i), y: .value("MB", v / 1_048_576))
                                .foregroundStyle(group.category.color)
                                .interpolationMethod(.monotone)
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                                AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d)) MB").font(.system(size: 9)) } }
                            }
                        }
                        .frame(height: 90)
                    }
                }

                actions

                section("Süreçler", icon: "cpu") {
                    VStack(spacing: 0) {
                        ForEach(group.processes.prefix(40)) { p in
                            HStack(spacing: 8) {
                                Text(verbatim: String(p.pid)).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.secondaryText)
                                    .frame(width: 48, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name).font(.system(size: 11.5)).lineLimit(1).truncationMode(.middle)
                                    if let cmd = p.command {
                                        Text(cmd).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(Theme.secondaryText)
                                            .lineLimit(1).truncationMode(.middle).help(cmd)
                                    }
                                }
                                Spacer(minLength: 6)
                                Text(p.memory.memString + (p.isFootprint ? "" : "*")).font(.system(size: 11.5, weight: .medium, design: .rounded)).monospacedDigit()
                            }
                            .padding(.vertical, 4)
                            Divider().opacity(0.25)
                        }
                        if group.processes.contains(where: { !$0.isFootprint }) {
                            Text("* Sistem sürecinin yerleşik belleği (RSS); gerçek kullanım biraz farklı olabilir.")
                                .font(.system(size: 10)).foregroundStyle(Theme.secondaryText).padding(.top, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                section("Konum", icon: "folder.fill") {
                    Text(group.bundlePath ?? group.executablePath)
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.secondaryText)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { quitButton; forceButton; revealButton }
                VStack(spacing: 8) {
                    quitButton
                    HStack(spacing: 8) { forceButton; revealButton }
                }
            }
            .controlSize(.large)
            .disabled(!group.canQuit)
            if let reason = group.quitBlockReason {
                Label(reason, systemImage: "lock.fill").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var quitButton: some View {
        Button { store.requestQuit(group) } label: {
            Label(group.category == .system ? "Yeniden Başlat" : "Kapat", systemImage: "xmark.circle")
                .lineLimit(1).fixedSize().frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).tint(group.category == .system ? .gray : .accentColor)
    }

    private var forceButton: some View {
        Button { store.requestQuit(group, force: true) } label: {
            Label("Zorla Kapat", systemImage: "bolt.circle").lineLimit(1).fixedSize().frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).tint(.red)
    }

    private var revealButton: some View {
        Button { store.revealInFinder(group) } label: { Image(systemName: "magnifyingglass") }
            .buttonStyle(.bordered).help("Finder'da göster")
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText)
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func section<C: View>(_ title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText)
            content()
        }
    }
}
