import SwiftUI

struct MaintenanceView: View {
    @Environment(MemoryStore.self) private var store
    var fixedWidth: CGFloat? = nil

    var body: some View {
        WidthReader(fixedWidth: fixedWidth) { w in content(width: w - 48) }
            .onAppear { store.reloadLaunchItems() }
    }

    private func content(width: CGFloat) -> some View {
        let wide = width >= 960
        return VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Bakım & Optimize",
                       subtitle: "Belleği boşaltın, gereksiz uygulamaları toplu kapatın, otomatik başlayanları görün.") {
                RefreshControl()
            }

            if wide {
                HStack(alignment: .top, spacing: 16) {
                    OptimizeHeroCard()
                    VStack(spacing: 16) {
                        ActionCard(action: .purge, accent: Theme.cached)
                        ActionCard(action: .release, accent: Theme.compressed)
                    }
                    .frame(width: 340)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                OptimizeHeroCard()
                HStack(alignment: .top, spacing: 16) {
                    ActionCard(action: .purge, accent: Theme.cached)
                    ActionCard(action: .release, accent: Theme.compressed)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            HowItWorksCard(stacked: width < 820)
            BulkQuitCard(columns: width >= 820 ? 2 : 1)
            LaunchItemsCard(compact: width < 820)
        }
        .padding(24)
    }
}

// MARK: - Tek tıkla optimize

struct OptimizeHeroCard: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        let running = store.maintenanceRunning
        let s = store.system
        Card(title: "Tek Tıkla Optimize", icon: "wand.and.stars", accent: ProcCategory.developer.color) {
            HStack(alignment: .center, spacing: 22) {
                ZStack {
                    MemoryRing(segments: [
                        RingSegment(fraction: Double(s.app) / Double(max(s.total, 1)), color: Theme.app),
                        RingSegment(fraction: Double(s.wired) / Double(max(s.total, 1)), color: Theme.wired),
                        RingSegment(fraction: Double(s.compressed) / Double(max(s.total, 1)), color: Theme.compressed),
                        RingSegment(fraction: Double(s.cached) / Double(max(s.total, 1)), color: Theme.cached.opacity(0.45)),
                    ], lineWidth: 14)
                    VStack(spacing: 0) {
                        Text(s.free.gb.fmt(1)).font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("GB boş").font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText)
                    }
                }
                .frame(width: 130, height: 130)

                VStack(alignment: .leading, spacing: 10) {
                    Text(MaintenanceAction.optimize.explanation)
                        .font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button {
                            store.runMaintenance(.optimize)
                        } label: {
                            HStack(spacing: 6) {
                                if running == .optimize { ProgressView().controlSize(.small) } else { Image(systemName: "wand.and.stars") }
                                Text(running == .optimize ? "Optimize ediliyor…" : "Şimdi Optimize Et")
                            }
                            .frame(minWidth: 170)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .tint(ProcCategory.developer.color.opacity(0.85))
                        .disabled(running != nil)

                        Button { store.runMaintenance(.releaseDeep) } label: {
                            Label("Derin Boşaltma", systemImage: MaintenanceAction.releaseDeep.icon)
                        }
                        .buttonStyle(.bordered).controlSize(.large)
                        .disabled(running != nil)
                        .help(MaintenanceAction.releaseDeep.explanation)
                    }
                    Label("macOS yönetici şifresini sorar; şifre MemScope'a iletilmez.", systemImage: "lock.shield")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText)
                }
            }
            if let r = store.lastResult { ResultView(result: r) }
        }
    }
}

struct ResultView: View {
    let result: MaintenanceResult

    var body: some View {
        if let err = result.error {
            Label("\(result.action.title): \(err)", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12)).foregroundStyle(Theme.wired)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wired.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(result.action.title) tamamlandı · \(result.date.formatted(date: .omitted, time: .shortened))",
                      systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.pressureColor(.normal))
                HStack(spacing: 10) {
                    delta("Boş bellek", result.before.free, result.after.free, goodWhenUp: true)
                    delta("Önbellek", result.before.cached, result.after.cached, goodWhenUp: false)
                    delta("Kullanılan", result.before.used, result.after.used, goodWhenUp: false)
                }
                Text("Not: macOS boş belleği zamanla yeniden önbellek olarak kullanır. Bu normaldir ve performansı artırır.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText)
            }
            .padding(12)
            .background(Theme.pressureColor(.normal).opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func delta(_ title: String, _ before: UInt64, _ after: UInt64, goodWhenUp: Bool) -> some View {
        let d = Int64(after) - Int64(before)
        let good = goodWhenUp ? d > 0 : d < 0
        return VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText)
            Text("\(before.memString) → \(after.memString)").font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
            Text((d >= 0 ? "+" : "−") + UInt64(abs(d)).memString)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(d == 0 ? Theme.secondaryText : (good ? Theme.pressureColor(.normal) : Theme.wired))
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ActionCard: View {
    @Environment(MemoryStore.self) private var store
    let action: MaintenanceAction
    let accent: Color

    var body: some View {
        Card(title: action.title, icon: action.icon, accent: accent) {
            Text(action.explanation).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if action == .purge {
                    Text("Şu an \(store.system.cached.memString) önbellek").font(.system(size: 11, weight: .medium))
                }
                Spacer()
                Button {
                    store.runMaintenance(action)
                } label: {
                    HStack(spacing: 5) {
                        if store.maintenanceRunning == action { ProgressView().controlSize(.mini) }
                        Text("Çalıştır")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(store.maintenanceRunning != nil)
            }
        }
    }
}

struct HowItWorksCard: View {
    var stacked = false

    var body: some View {
        Card(title: "Bu işlemler ne yapar, ne yapmaz?", icon: "info.circle.fill", accent: Theme.app) {
            let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            layout {
                bullet("checkmark.circle.fill", Theme.pressureColor(.normal),
                       "Dosya önbelleğini boşaltır ve uygulamalara önbelleklerini bırakmalarını söyler. Ağır bir iş (oyun, render, VM) başlatmadan önce faydalıdır.")
                bullet("arrow.triangle.2.circlepath", Theme.compressed,
                       "macOS belleği zaten otomatik sıkıştırır. Bu işlemler sadece bunu hemen yaptırır; sürekli çalıştırmaya gerek yoktur.")
                bullet("xmark.octagon.fill", Theme.wired,
                       "Kalıcı kazanç için en etkili yol, kullanmadığınız uygulamaları kapatmak ve gereksiz otomatik başlayanları kaldırmaktır (aşağıda).")
            }
        }
    }

    private func bullet(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Toplu kapatma

struct BulkQuitCard: View {
    @Environment(MemoryStore.self) private var store
    var columns = 2
    @State private var selected: Set<String> = []
    @State private var initialized = false
    @State private var confirm = false

    var body: some View {
        let candidates = store.groups.filter { ($0.category == .app || $0.category == .background || $0.category == .developer) && $0.canQuit && $0.memory > 50 * 1_048_576 }
        let chosen = candidates.filter { selected.contains($0.id) }
        let total = chosen.reduce(0) { $0 + $1.memory }

        Card(title: "Toplu Kapatma", icon: "checklist", accent: ProcCategory.background.color) {
            HStack(spacing: 10) {
                Button("Arka planları seç") { selected = Set(candidates.filter { $0.category == .background }.map(\.id)) }
                Button("Temizle") { selected.removeAll() }
            }
            .buttonStyle(.borderless).font(.system(size: 11.5))
        } content: {
            Text("Kapatmak istediklerinizi işaretleyin. Uygulamalara normal kapanma sinyali gönderilir; kaydetmeniz istenebilir.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
            if candidates.isEmpty {
                Label("Kapatılabilecek uygun bir şey yok.", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.pressureColor(.normal))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 6) {
                ForEach(candidates) { g in
                    Toggle(isOn: Binding(get: { selected.contains(g.id) },
                                         set: { if $0 { selected.insert(g.id) } else { selected.remove(g.id) } })) {
                        HStack(spacing: 8) {
                            GroupIcon(group: g, size: 20)
                            Text(g.displayName).font(.system(size: 12)).lineLimit(1)
                            if let hint = g.commandHint {
                                Text(hint).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(ProcCategory.developer.color).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            CategoryBadge(category: g.category, compact: true)
                            Text(g.memory.memString).font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
                                .frame(width: 68, alignment: .trailing)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.vertical, 3).padding(.horizontal, 6)
                    .background(selected.contains(g.id) ? g.category.color.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            HStack {
                Text(chosen.isEmpty ? "Seçim yok" : "\(chosen.count) öğe · ~\(total.memString) serbest kalacak")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Seçilenleri Kapat") { confirm = true }
                    .buttonStyle(.borderedProminent).disabled(chosen.isEmpty)
            }
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            selected = Set(candidates.filter { $0.category == .background }.map(\.id))
        }
        .alert("\(chosen.count) öğe kapatılsın mı?", isPresented: $confirm) {
            Button("Kapat", role: .destructive) { store.quitMany(chosen); selected.removeAll() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text(chosen.map(\.displayName).joined(separator: ", ") + "\n\nYaklaşık \(total.memString) bellek serbest kalacak. Kaydedilmemiş değişiklikler için uygulamalar sizden onay isteyebilir.")
        }
    }
}

// MARK: - Otomatik başlayanlar

struct LaunchItemsCard: View {
    @Environment(MemoryStore.self) private var store
    var compact = false

    var body: some View {
        Card(title: "Otomatik Başlayanlar", icon: "power.circle.fill", accent: Theme.swap) {
            HStack(spacing: 10) {
                Button { store.reloadLaunchItems() } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                Button { store.openLoginItemsSettings() } label: { Label("Giriş Öğeleri Ayarları", systemImage: "gearshape") }
            }
            .buttonStyle(.borderless).font(.system(size: 11.5))
        } content: {
            Text("Mac açıldığında veya oturum açtığınızda kendiliğinden çalışan üçüncü taraf ajanlar. Kullanmadığınız bir yazılıma aitse, ilgili uygulamanın ayarlarından veya Sistem Ayarları → Genel → Giriş Öğeleri'nden kapatabilirsiniz.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)

            if store.launchItems.isEmpty {
                Text("Üçüncü taraf başlangıç ajanı bulunamadı.").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
            VStack(spacing: 0) {
                ForEach(store.launchItems) { item in
                    let running = store.runningGroup(for: item)
                    HStack(spacing: 10) {
                        Circle().fill(running != nil ? Theme.pressureColor(.normal) : Color.white.opacity(0.2)).frame(width: 7, height: 7)
                            .help(running != nil ? "Şu an çalışıyor" : "Şu an çalışmıyor")
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.vendor).font(.system(size: 12.5, weight: .semibold))
                                Text(item.displayName).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                            }
                            Text(item.label).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if !compact { tag(item.scope.rawValue, Theme.app) }
                        if item.keepAlive { tag("Sürekli açık", Theme.wired) }
                        else if item.runAtLoad { tag("Açılışta", ProcCategory.background.color) }
                        if item.disabled { tag("Devre dışı", .gray) }
                        Text(running.map { $0.memory.memString } ?? "—")
                            .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                        Button { store.revealPath(item.plistPath) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless).help("Tanım dosyasını Finder'da göster")
                        if let g = running {
                            Button { store.open(g) } label: { Image(systemName: "info.circle") }
                                .buttonStyle(.borderless).help("Süreç ayrıntıları")
                        }
                    }
                    .padding(.vertical, 7)
                    Divider().opacity(0.25)
                }
            }
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.13), in: Capsule())
    }
}
