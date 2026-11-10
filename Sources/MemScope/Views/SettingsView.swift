import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(Notifier.pressureKey) private var notifyPressure = true
    @AppStorage(Notifier.swapKey) private var notifySwap = true
    @AppStorage(Notifier.growthKey) private var notifyGrowth = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ayarlar").font(.system(size: 28, weight: .bold, design: .rounded))

                Card(title: "Genel", icon: "gearshape.fill", accent: Theme.app) {
                    Toggle(isOn: $launchAtLogin) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Oturum açılışında başlat")
                            Text("MemScope menü çubuğunda arka planda çalışır ve geçmiş kaydını sürdürür.")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                    if let loginError {
                        Label(loginError, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Theme.wired)
                    }
                    if !Bundle.main.bundlePath.hasPrefix("/Applications/") {
                        Label("Oturum açılışında başlatma için MemScope'un /Applications klasöründe olması önerilir.", systemImage: "info.circle")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                    }
                    Divider().opacity(0.3)
                    HStack {
                        Text("Yenileme aralığı")
                        Spacer()
                        Picker("", selection: $store.interval) {
                            ForEach(MemoryStore.intervalChoices, id: \.self) { Text("\(Int($0)) saniye").tag($0) }
                        }
                        .labelsHidden().frame(width: 140)
                    }
                }

                Card(title: "Bildirimler", icon: "bell.badge.fill", accent: ProcCategory.background.color) {
                    Toggle("Bellek basıncı Uyarı veya Kritik seviyeye çıktığında", isOn: $notifyPressure)
                    Toggle("Swap kullanımı 4 GB'ı aştığında", isOn: $notifySwap)
                    Toggle("Bir uygulama 1 dakikada 500 MB'tan fazla büyüdüğünde", isOn: $notifyGrowth)
                    Text("Aynı bildirim en fazla 15 dakikada bir gönderilir.").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                }
                .toggleStyle(.switch)
                .onChange(of: notifyPressure) { _, on in if on { Notifier.shared.requestAuthorization() } }
                .onChange(of: notifySwap) { _, on in if on { Notifier.shared.requestAuthorization() } }
                .onChange(of: notifyGrowth) { _, on in if on { Notifier.shared.requestAuthorization() } }

                Card(title: "Veri", icon: "internaldrive.fill", accent: Theme.cached) {
                    Text("Dakikalık bellek geçmişi son 7 gün için saklanır: \(store.longHistory.count) kayıt.")
                        .font(.system(size: 12))
                    Text("~/Library/Application Support/MemScope/history.json")
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.secondaryText).textSelection(.enabled)
                }

                Card(title: "Hakkında", icon: "memorychip.fill", accent: Theme.compressed) {
                    Text("MemScope \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · açık kaynak bellek yöneticisi")
                        .font(.system(size: 12))
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .onAppear { if notifyPressure || notifySwap || notifyGrowth { Notifier.shared.requestAuthorization() } }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Ayarlanamadı: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
