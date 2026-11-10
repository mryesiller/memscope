# MemScope

**Mac için anlaşılır bellek yöneticisi.** Neyin ne kadar RAM kullandığını, her sürecin ne işe yaradığını ve kapatılmasının güvenli olup olmadığını Türkçe olarak gösterir. Tek tıkla önbellek temizleme ve bellek boşaltma yapar.

*A friendly, native macOS memory manager (SwiftUI). It explains what every process does, whether it is safe to quit, and can purge caches / ask apps to release memory. UI is in Turkish.*

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black) ![Swift](https://img.shields.io/badge/Swift-5.10%2B-orange) ![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-native-blue) ![License: MIT](https://img.shields.io/badge/License-MIT-green)

## Neden?

Activity Monitor yüzlerce `mds_stores`, `Claude Helper (Renderer)`, `photoanalysisd` gibi süreç gösterir ama hangisinin önemli, hangisinin gereksiz olduğunu söylemez. MemScope:

- Yardımcı süreçleri ait oldukları uygulamada toplar (ör. *Claude — 19 süreç — 1,8 GB*).
- Her birini 5 kategoriye ayırır: **Uygulama · Arka Plan · Geliştirici · Sistem · Kritik**.
- ~150 yaygın süreç için "Ne işe yarar?" ve "Önemli mi?" açıklaması ile ipuçları verir.
- RAM'in "dolu" görünmesinin neden çoğu zaman sorun olmadığını (önbellek, bellek basıncı) açıklar.

## Özellikler

| Ekran | İçerik |
|---|---|
| **Panel** | Kullanılan bellek halkası, Activity Monitor ile aynı dağılım (uygulama / kablolu / sıkıştırılmış / önbellek), bellek basıncı, swap, canlı / 1 saat / 24 saat / 7 gün geçmiş grafiği, kategori halkası, en çok kullananlar, "kapatılabilecekler" ve hızla büyüyen uygulama uyarısı |
| **Uygulamalar & Süreçler** | Gruplanmış liste, kategori filtreleri, arama (isim / yol / PID), komut satırı ipuçları (`python server.py`, `firecrawl-mcp`), ayrıntı paneli, bellek geçmişi, Kapat / Zorla Kapat |
| **Bakım & Optimize** | Tek tıkla optimize, önbellek temizleme (`purge`), bellek boşaltma (uygulamalara bellek uyarısı sinyali), önce/sonra karşılaştırması, toplu kapatma, otomatik başlayan ajanlar ve anlık bellek kullanımları |
| **Ayarlar** | Oturum açılışında başlatma, yenileme aralığı, bildirimler (basınç, swap, hızlı büyüme) |
| **Menü çubuğu** | Kullanım yüzdesi, mini özet, Hızlı Optimize |

## Kurulum

### Kaynaktan (önerilen)

Xcode veya Command Line Tools (Swift 5.10+) gerekir.

```bash
git clone https://github.com/mryesiller/memscope.git
cd memscope
./build.sh install     # derler, /Applications/MemScope.app olarak kurar ve başlatır
```

Sadece derlemek için `./build.sh` → `build/MemScope.app`.

### Hazır sürüm

[Releases](../../releases) sayfasından `MemScope.zip` indirin, açın ve `MemScope.app`'i Uygulamalar klasörüne taşıyın. Uygulama Apple Developer ID ile imzalı olmadığından ilk açılışta Gatekeeper uyarı verir:

```bash
xattr -dr com.apple.quarantine /Applications/MemScope.app
```

## Bakım işlemleri nasıl çalışır?

| İşlem | Komut | Etki |
|---|---|---|
| Önbelleği Temizle | `/usr/sbin/purge` | Disk önbelleğini boşaltır (önbellek → boş bellek) |
| Belleği Boşalt | `memory_pressure -S -l warn -s 4` | 4 sn yapay bellek uyarısı; uygulamalar önbelleklerini bırakır, macOS boştaki belleği sıkıştırır |
| Derin Boşaltma | `memory_pressure -S -l critical -s 4` | Aynısı, kritik seviyede |
| Tek Tıkla Optimize | ikisi birden | Tek şifre sorar |

- Komutlar sabittir ve macOS'un kendi yönetici şifresi penceresiyle (`osascript … with administrator privileges`) çalıştırılır. Şifre MemScope'a hiç iletilmez.
- macOS belleği zaten otomatik yönetir. Bu işlemler ağır bir iş öncesinde hemen yer açmak içindir; sürekli çalıştırmaya gerek yoktur. Kalıcı kazanç, kullanılmayan uygulamaları ve gereksiz otomatik başlayanları kapatmaktan gelir.

## Gizlilik

MemScope tamamen yereldir: ağ bağlantısı kurmaz, veri göndermez. Dakikalık bellek geçmişi (7 gün) yalnızca `~/Library/Application Support/MemScope/history.json` dosyasında tutulur.

## Teknik notlar

- Kendi kullanıcınızın süreçleri için bellek değeri Activity Monitor'daki "Bellek" sütunuyla aynıdır (`phys_footprint`, `proc_pid_rusage`). Root süreçleri için `ps` üzerinden RSS gösterilir (`*` ile işaretlidir).
- Sistem belleği `host_statistics64` ile Activity Monitor'ün formülüyle hesaplanır; bellek basıncı `kern.memorystatus_vm_pressure_level` sysctl'inden okunur.
- XPC yardımcıları (ör. Safari'nin WebContent süreçleri) "responsible PID" ile sahibi olan uygulamaya bağlanır.
- `MemScope --snapshot <klasör>` arayüzü ekran yakalamadan PNG olarak üretir (geliştirme amaçlı).

### Proje yapısı

```
Sources/MemScope/
├── MemScopeApp.swift        # App, pencere, menü çubuğu, ayarlar sahnesi
├── MemoryStore.swift        # Örnekleme döngüsü, durum, eylemler
├── SystemMemory.swift       # host_statistics64, swap, basınç
├── ProcessSampler.swift     # ps + proc_pid_rusage, gruplama, komut satırları
├── ProcessKnowledge.swift   # Süreç bilgi tabanı (açıklamalar / kategoriler)
├── Maintenance.swift        # purge / memory_pressure (yönetici izniyle)
├── LaunchItems.swift        # LaunchAgents / LaunchDaemons taraması
├── Notifier.swift           # Bildirimler
├── HistoryRecorder.swift    # 7 günlük dakikalık geçmiş
└── Views/                   # Panel, Süreçler, Bakım, Ayarlar, bileşenler
```

## Katkı

Bilgi tabanına yeni süreç eklemek en kolay katkı yoludur: `ProcessKnowledge.swift` içindeki `known` sözlüğüne bir satır ekleyin.

```swift
"surec_adi": Entry(.background, "Görünen Ad", "Ne işe yaradığı.", tip: "İsteğe bağlı ipucu."),
```

Hata bildirimleri ve öneriler için issue açabilirsiniz.

## Yol haritası

- [ ] Otomatik başlayan ajanları uygulama içinden devre dışı bırakma
- [ ] Uygulama başına uzun dönem bellek geçmişi ve "en çok büyüyenler" raporu
- [ ] Basınç yükseldiğinde otomatik optimize (isteğe bağlı)
- [ ] İngilizce arayüz
- [ ] Widget (masaüstü / Bildirim Merkezi)

## Lisans

[MIT](LICENSE)
