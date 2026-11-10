import SwiftUI
import AppKit

@main
struct MemScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = MemoryStore.shared

    var body: some Scene {
        Window("MemScope", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 960, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 880)

        Settings {
            SettingsView().environment(store).frame(width: 640, height: 620)
                .background(Theme.background).preferredColorScheme(.dark)
        }

        MenuBarExtra {
            MenuBarView().environment(store)
        } label: {
            let s = store.system
            Image(systemName: s.pressure == .normal ? "memorychip" : "memorychip.fill")
            Text("\(Int((s.usedFraction * 100).rounded()))%")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))   // birkaç örnek toplansın
                MemoryStore.shared.reloadLaunchItems()
                try? await Task.sleep(for: .seconds(1))
                Snapshot.render(to: dir)
                NSApp.terminate(nil)
            }
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { MemoryStore.shared.recorder.save() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct ContentView: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(selection: $store.section) {
                Section("MemScope") {
                    ForEach(AppSection.allCases) { s in
                        Label(s.title, systemImage: s.icon).tag(s)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            ZStack {
                Theme.background.ignoresSafeArea()
                switch store.section ?? .dashboard {
                case .dashboard: DashboardView()
                case .processes: ProcessesView()
                case .maintenance: MaintenanceView()
                case .settings: SettingsView()
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert(item: $store.quitRequest) { req in
            let g = req.group
            let msg: String = {
                var m = "Yaklaşık \(g.memory.memString) bellek serbest kalacak."
                switch g.category {
                case .app: m += " Kaydedilmemiş değişiklikler kaybolabilir."
                case .system: m += " Bu bir macOS servisidir; macOS gerekirse otomatik yeniden başlatır."
                case .developer: m += " Çalışan bir sunucu veya iş varsa durdurulur."
                default: break
                }
                if req.force { m += "\n\nZorla kapatma, uygulamaya kaydetme fırsatı vermez." }
                return m
            }()
            return Alert(
                title: Text("“\(g.displayName)” \(req.force ? "zorla " : "")kapatılsın mı?"),
                message: Text(msg),
                primaryButton: .destructive(Text(req.force ? "Zorla Kapat" : "Kapat")) { store.performQuit(req) },
                secondaryButton: .cancel(Text("Vazgeç")))
        }
    }

    private var sidebarFooter: some View {
        let s = store.system
        let c = Theme.pressureColor(s.pressure)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(c).frame(width: 8, height: 8)
                Text("Basınç: \(s.pressure.title)").font(.system(size: 11.5, weight: .medium))
                Spacer()
            }
            MeterBar(fraction: s.usedFraction, color: c, height: 5)
            Text("\(s.used.memString) / \(s.total.memString)").font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

struct MenuBarView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let s = store.system
        let t = Double(max(s.total, 1))
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ZStack {
                    MemoryRing(segments: [
                        RingSegment(fraction: Double(s.app) / t, color: Theme.app),
                        RingSegment(fraction: Double(s.wired) / t, color: Theme.wired),
                        RingSegment(fraction: Double(s.compressed) / t, color: Theme.compressed),
                    ], lineWidth: 9)
                    Text("\(Int((s.usedFraction * 100).rounded()))%").font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(s.used.memString) kullanımda").font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 5) {
                        Circle().fill(Theme.pressureColor(s.pressure)).frame(width: 7, height: 7)
                        Text("Basınç: \(s.pressure.title)").font(.system(size: 11.5))
                    }
                    Text("Swap: \(s.swapUsed.memString)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            Divider()
            Text("En çok kullananlar").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            VStack(spacing: 7) {
                ForEach(store.groups.prefix(6)) { g in
                    HStack(spacing: 8) {
                        GroupIcon(group: g, size: 18)
                        Text(g.displayName).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        Text(g.memory.memString).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                    }
                }
            }
            if store.reclaimable > 0 {
                Text("~\(store.reclaimable.memString) güvenle geri kazanılabilir")
                    .font(.system(size: 11)).foregroundStyle(ProcCategory.developer.color)
            }
            Divider()
            Button {
                store.runMaintenance(.optimize)
            } label: {
                HStack {
                    if store.maintenanceRunning != nil { ProgressView().controlSize(.small) } else { Image(systemName: "wand.and.stars") }
                    Text(store.maintenanceRunning != nil ? "Optimize ediliyor…" : "Hızlı Optimize")
                    Spacer()
                    if let r = store.lastResult, r.error == nil, r.freedFree > 0 {
                        Text("+\(UInt64(r.freedFree).memString)").foregroundStyle(ProcCategory.developer.color)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(store.maintenanceRunning != nil)
            HStack {
                Button("Paneli Aç") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("Çık") { NSApp.terminate(nil) }.buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

/// Geliştirme amaçlı: ekranı yakalamadan arayüzü PNG olarak üretir (`MemScope --snapshot <klasör>`).
@MainActor
enum Snapshot {
    static func render(to dir: URL) {
        let store = MemoryStore.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        write(DashboardView(fixedWidth: 1240), "dashboard", dir)
        write(DashboardView(fixedWidth: 760), "dashboard-narrow", dir)
        write(ProcessesView().frame(width: 760, height: 420), "processes-narrow", dir)
        write(ProcessesView().frame(width: 1100, height: 420), "processes-wide", dir)
        let rows = VStack(spacing: 2) {
            ForEach(store.groups.prefix(18)) { GroupRow(group: $0, maxMem: Double(store.groups.first?.memory ?? 1)) }
        }.padding(20).frame(width: 760)
        write(rows, "processes", dir)
        if let g = store.groups.first(where: { $0.category == .app }) {
            write(InspectorView(group: g, scrollable: false).frame(width: 400), "inspector", dir)
            write(InspectorView(group: g, scrollable: false).frame(width: 300), "inspector-narrow", dir)
        }
        if let g = store.groups.first(where: { $0.category == .system || $0.category == .critical }) {
            write(InspectorView(group: g, scrollable: false).frame(width: 400), "inspector-system", dir)
        }
        write(MenuBarView(), "menubar", dir)
        store.reloadLaunchItems()
        write(MaintenanceView(fixedWidth: 1240), "maintenance", dir)
        write(MaintenanceView(fixedWidth: 760), "maintenance-narrow", dir)
    }

    private static func write<V: View>(_ view: V, _ name: String, _ dir: URL) {
        let content = view.environment(MemoryStore.shared).background(Theme.background).environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: content)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent(name + ".png"))
    }
}
