import SwiftUI

/// Yenileme aralığı seçimi ve duraklatma.
struct RefreshControl: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 10) {
            LiveDot(color: store.paused ? .gray : Theme.pressureColor(store.system.pressure))
            Text(store.paused ? "Duraklatıldı" : "Canlı").font(.system(size: 12, weight: .medium))
            Picker("", selection: $store.interval) {
                ForEach(MemoryStore.intervalChoices, id: \.self) { Text("her \(Int($0)) sn").tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
            .disabled(store.paused)
            Button { store.paused.toggle() } label: {
                Image(systemName: store.paused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.borderless)
            .help(store.paused ? "Canlı güncellemeyi sürdür" : "Ekranı dondur (değerler güncellenmez)")
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Color.white.opacity(0.05), in: Capsule())
    }
}
