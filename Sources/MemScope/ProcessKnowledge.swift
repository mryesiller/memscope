import Foundation

/// Süreçlerin ne işe yaradığını ve önemli olup olmadığını açıklayan bilgi tabanı.
enum ProcessKnowledge {
    struct Classification: Sendable {
        let category: ProcCategory
        let title: String?
        let summary: String
        let tip: String?
    }

    private struct Entry {
        let cat: ProcCategory
        let title: String?
        let summary: String
        let tip: String?
        init(_ cat: ProcCategory, _ title: String? = nil, _ summary: String, tip: String? = nil) {
            self.cat = cat; self.title = title; self.summary = summary; self.tip = tip
        }
    }

    static func classify(name: String, execPath: String, bundle: String?) -> Classification {
        let execName = (execPath as NSString).lastPathComponent.lowercased()
        let lname = name.lowercased()

        if (bundle ?? execPath).contains("/claude-code/") {
            return Classification(category: .developer, title: "Claude Code",
                                  summary: "Claude Code komut satırı ajanı. Her açık oturum ayrı bir süreçtir; başlattığı araçlar (MCP sunucuları, node) ayrıca listelenir.",
                                  tip: "Kullanmadığınız Claude Code oturumlarını kapatmak belleği azaltır.")
        }

        for key in [lname, execName] {
            if let e = known[key] { return Classification(category: e.cat, title: e.title, summary: e.summary, tip: e.tip) }
        }
        for (prefix, e) in prefixes where execName.hasPrefix(prefix) || lname.hasPrefix(prefix) {
            return Classification(category: e.cat, title: e.title, summary: e.summary, tip: e.tip)
        }
        return pathRule(name: lname, path: bundle ?? execPath, isBundle: bundle != nil)
    }

    private static func pathRule(name: String, path: String, isBundle: Bool) -> Classification {
        let isApple = path.hasPrefix("/System/") || path.hasPrefix("/usr/") || path.hasPrefix("/sbin/") || path.hasPrefix("/bin/")
        let looksLikeUpdater = name.contains("update") || name.contains("updater")

        if path.hasPrefix("/System/Applications/") || path.contains("/Cryptexes/App/System/Applications/") {
            return .init(category: .app, title: nil,
                         summary: "macOS ile birlikte gelen bir Apple uygulaması. Açıksa sizin (veya bir kısayolun) açtığı anlamına gelir.",
                         tip: nil)
        }
        if !isApple && looksLikeUpdater {
            return .init(category: .background, title: nil,
                         summary: "Bir uygulamanın güncelleme denetleyicisi. Arka planda yeni sürüm olup olmadığını kontrol eder.",
                         tip: "Kapatmak tamamen güvenlidir; uygulama bir sonraki açılışta tekrar kontrol eder.")
        }
        if path.contains("/Applications/") && isBundle && !path.hasPrefix("/System/") {
            if path.contains("/Library/LoginItems/") || path.contains("/Library/Helpers/") {
                return .init(category: .background, title: nil,
                             summary: "Bir uygulamanın oturum açılışında otomatik başlayan yardımcısı.",
                             tip: "Sistem Ayarları → Genel → Giriş Öğeleri'nden otomatik başlamasını kapatabilirsiniz.")
            }
            return .init(category: .app, title: nil,
                         summary: "Sizin yüklediğiniz bir uygulama. Bellek değeri, uygulamanın tüm yardımcı süreçlerinin toplamıdır.",
                         tip: nil)
        }
        if isApple {
            return .init(category: .system, title: nil,
                         summary: "macOS'un dahili bir servisi (daemon). Çoğu belgelenmemiştir; sistem gerektiğinde çalıştırır.",
                         tip: nil)
        }
        let devMarkers = ["/opt/homebrew/", "/usr/local/", "/.nvm/", "/.pyenv/", "/.cargo/", "/node_modules/", "/.local/bin/", "/.bun/", "/.volta/", "/.rbenv/", "/.sdkman/"]
        if devMarkers.contains(where: path.contains) || !path.hasPrefix("/") {
            return .init(category: .developer, title: nil,
                         summary: "Terminalden veya bir geliştirme aracından çalıştırılan bir program (Homebrew, Node, Python vb.).",
                         tip: nil)
        }
        if path.contains("/Library/") {
            return .init(category: .background, title: nil,
                         summary: "Üçüncü taraf bir yazılımın arka plan aracı (ajan, senkronizasyon, sürücü yardımcısı vb.).",
                         tip: "Hangi uygulamaya ait olduğunu yoldan anlayabilirsiniz. Kullanmadığınız bir yazılımsa kaldırmayı düşünün.")
        }
        return .init(category: .background, title: nil,
                     summary: "Tanımlanamayan bir süreç. Aşağıdaki dosya yolu hangi yazılıma ait olduğunu gösterir.",
                     tip: nil)
    }

    // MARK: - Önek eşleşmeleri

    private static let prefixes: [(String, Entry)] = [
        ("com.apple.webkit.webcontent", Entry(.system, "Web İçeriği", "Bir web sayfasının içeriğini çalıştırır (Safari, Mail veya web görünümü kullanan bir uygulama için). Her sekme ayrı bir süreç olabilir.", tip: "Bellek yüksekse açık sekme sayısını azaltın.")),
        ("com.apple.webkit", Entry(.system, "WebKit Servisi", "Web sayfalarının ağ ve grafik işlemlerini yürüten WebKit yardımcısı.")),
        ("com.apple.virtualization", Entry(.developer, "Sanal Makine", "Bir sanal makine çalıştırıyor (Docker, OrbStack, UTM, Parallels vb.). Ayrılan RAM'in tamamını tutabilir.", tip: "İlgili uygulamanın ayarlarından sanal makineye ayrılan belleği düşürebilirsiniz.")),
        ("com.apple.appkit.xpc", Entry(.system, "Aç/Kaydet Paneli", "Uygulamalardaki 'Aç' ve 'Kaydet' pencerelerini sağlar.")),
        ("com.apple.", Entry(.system, nil, "macOS'un dahili bir yardımcı servisi.")),
        ("mdworker", Entry(.system, "Spotlight Çalışanı", "Spotlight için dosyalarınızın içeriğini okuyup indeksler. Çok sayıda kopyası olması normaldir.", tip: "Yeni dosya kopyaladıktan sonra geçici olarak artar, sonra kendiliğinden kapanır.")),
        ("npm exec", Entry(.developer, "npm / MCP Sunucusu", "npm ile başlatılmış bir Node.js aracı. Çoğunlukla Claude gibi uygulamaların kullandığı MCP sunucularıdır.", tip: "Bunları başlatan uygulamayı kapatınca genellikle onlar da kapanır.")),
        ("canon", Entry(.background, "Canon Yazıcı Aracı", "Canon yazıcı sürücüsünün arka plan ajanı (durum izleme, anket, tarama).", tip: "Yazıcıyı sık kullanmıyorsanız kapatmak güvenlidir.")),
        ("jp.co.canon", Entry(.background, "Canon Yazıcı Aracı", "Canon yazıcı sürücüsünün arka plan ajanı.", tip: "Yazıcıyı sık kullanmıyorsanız kapatmak güvenlidir.")),
        ("kpm", Entry(.background, "Kaspersky Password Manager", "Kaspersky parola yöneticisinin arka plan servisi.")),
        ("ksec", Entry(.system, "Kaspersky Güvenlik", "Kaspersky güvenlik yazılımının arka plan servisi.", tip: "Güvenlik yazılımı olduğu için kapatmanız önerilmez.")),
    ]

    // MARK: - Bilinen süreçler (küçük harf)

    private static let known: [String: Entry] = [
        // Kritik
        "kernel_task": Entry(.critical, "macOS Çekirdeği", "İşletim sisteminin kalbi. Donanımı, belleği ve ısıyı yönetir."),
        "launchd": Entry(.critical, "launchd", "Sistem başlatıcısı (PID 1). Diğer tüm süreçleri başlatır ve denetler."),
        "windowserver": Entry(.critical, "WindowServer", "Ekrandaki her pencereyi, animasyonu ve imleci çizer. Yüksek çözünürlüklü veya çoklu monitörde 1–3 GB kullanması normaldir.", tip: "Çok sayıda açık pencere, hareketli duvar kağıdı ve şeffaflık efektleri kullanımını artırır."),
        "loginwindow": Entry(.critical, "loginwindow", "Oturumunuzu yönetir. Kapatılırsa oturum sonlanır."),
        "logd": Entry(.critical, "logd", "Sistem günlüklerini (log) toplar ve saklar."),
        "configd": Entry(.critical, "configd", "Ağ ve sistem yapılandırmasını yönetir."),
        "notifyd": Entry(.critical, "notifyd", "Süreçler arası sistem bildirimlerini iletir."),
        "securityd": Entry(.critical, "securityd", "Anahtar Zinciri ve şifreleme işlemlerini yürütür."),
        "opendirectoryd": Entry(.critical, "opendirectoryd", "Kullanıcı hesapları ve kimlik doğrulamayı yönetir."),
        "diskarbitrationd": Entry(.critical, "diskarbitrationd", "Diskleri ve USB sürücüleri bağlar/ayırır."),
        "fseventsd": Entry(.critical, "fseventsd", "Dosya sistemi değişikliklerini izler (Spotlight, Time Machine bunu kullanır)."),
        "coreservicesd": Entry(.critical, "coreservicesd", "Uygulama başlatma ve dosya ilişkilendirmelerinin temel servisi."),
        "runningboardd": Entry(.critical, "runningboardd", "Uygulamaların yaşam döngüsünü ve kaynak önceliklerini yönetir."),
        "powerd": Entry(.critical, "powerd", "Uyku, enerji ve güç yönetimi."),
        "kernelmanagerd": Entry(.critical, "kernelmanagerd", "Çekirdek uzantılarını (sürücüleri) yönetir."),
        "watchdogd": Entry(.critical, "watchdogd", "Sistem donmalarını algılar ve kurtarır."),
        "cfprefsd": Entry(.critical, "cfprefsd", "Tüm uygulama ayarlarını (tercihleri) okur ve yazar."),

        // macOS servisleri
        "finder": Entry(.system, "Finder", "Dosya yöneticisi ve masaüstü. Kapatılırsa macOS otomatik yeniden açar."),
        "dock": Entry(.system, "Dock", "Dock, Launchpad ve Mission Control'ü çalıştırır. Kapatılırsa otomatik yeniden başlar."),
        "systemuiserver": Entry(.system, "SystemUIServer", "Menü çubuğundaki sistem simgelerini yönetir."),
        "controlcenter": Entry(.system, "Denetim Merkezi", "Denetim Merkezi ve menü çubuğundaki Wi‑Fi, ses, pil gibi öğeler."),
        "notificationcenter": Entry(.system, "Bildirim Merkezi", "Bildirimleri ve masaüstü widget'larını gösterir.", tip: "Çok sayıda widget eklediyseniz bellek kullanımı artar."),
        "chronod": Entry(.system, "Widget Servisi", "Masaüstü ve Bildirim Merkezi widget'larının içeriğini günceller."),
        "spotlight": Entry(.system, "Spotlight", "Spotlight arama arayüzü."),
        "mds": Entry(.system, "Spotlight Sunucusu", "Spotlight indeksinin ana servisi. Arama yapabilmeniz için dosyaları takip eder."),
        "mds_stores": Entry(.system, "Spotlight Veritabanı", "Spotlight arama veritabanını yönetir. İndeksleme sırasında geçici olarak çok bellek kullanabilir.", tip: "Sürekli yüksekse Sistem Ayarları → Spotlight'tan gereksiz klasörleri hariç tutun."),
        "corespotlightd": Entry(.system, "Core Spotlight", "Uygulama içi içerikleri (mesaj, not vb.) Spotlight'a ekler."),
        "backupd": Entry(.system, "Time Machine", "Time Machine yedeklemelerini yapar. Yedekleme sırasında aktiftir."),
        "cloudd": Entry(.system, "iCloud", "iCloud verilerini (CloudKit) senkronize eder."),
        "bird": Entry(.system, "iCloud Drive", "iCloud Drive dosya senkronizasyonu."),
        "fileproviderd": Entry(.system, "Dosya Sağlayıcı", "iCloud Drive, Dropbox, Google Drive gibi bulut klasörlerini Finder'a bağlar."),
        "photoanalysisd": Entry(.system, "Fotoğraf Analizi", "Fotoğraflar arşivinizdeki yüzleri, nesneleri ve anıları analiz eder.", tip: "Mac boştayken çalışır ve iş bitince azalır. Geçici yüksek kullanım normaldir."),
        "mediaanalysisd": Entry(.system, "Medya Analizi", "Fotoğraf ve videolarda metin, nesne ve sahne tanıma (Canlı Metin, Görsel Arama) yapar.", tip: "Geçicidir; analiz bitince belleği bırakır."),
        "photolibraryd": Entry(.system, "Fotoğraf Arşivi", "Fotoğraflar arşivine erişimi yönetir."),
        "cloudphotod": Entry(.system, "iCloud Fotoğraflar", "Fotoğraflarınızı iCloud ile senkronize eder."),
        "coreaudiod": Entry(.system, "Ses Servisi", "Tüm ses giriş/çıkışını yönetir."),
        "bluetoothd": Entry(.system, "Bluetooth", "Bluetooth cihazlarını (klavye, kulaklık) yönetir."),
        "airportd": Entry(.system, "Wi‑Fi", "Wi‑Fi bağlantısını yönetir."),
        "mdnsresponder": Entry(.system, "DNS / Bonjour", "Alan adı çözümleme ve yerel ağ cihaz keşfi. İnternet için gereklidir."),
        "trustd": Entry(.system, "Sertifika Doğrulama", "Web siteleri ve uygulamalar için sertifikaları doğrular."),
        "secd": Entry(.system, "Anahtar Zinciri Senkronizasyonu", "iCloud Anahtar Zinciri'ni yönetir."),
        "syspolicyd": Entry(.system, "Gatekeeper", "Uygulamaların güvenli olup olmadığını denetler."),
        "xprotectservice": Entry(.system, "XProtect", "macOS'un yerleşik kötü amaçlı yazılım tarayıcısı."),
        "tccd": Entry(.system, "Gizlilik İzinleri", "Kamera, mikrofon, dosya erişimi gibi izinleri yönetir."),
        "lsd": Entry(.system, "Launch Services", "Hangi dosyanın hangi uygulamayla açılacağını bilir."),
        "usereventagent": Entry(.system, "UserEventAgent", "Sistem olaylarını dinleyip ilgili servisleri tetikler."),
        "distnoted": Entry(.system, "distnoted", "Uygulamalar arası bildirim dağıtımı."),
        "sharingd": Entry(.system, "AirDrop & Handoff", "AirDrop, Handoff ve evrensel pano özelliklerini çalıştırır."),
        "rapportd": Entry(.system, "Cihazlar Arası İletişim", "iPhone, iPad ve Apple Watch ile yakın cihaz iletişimini sağlar."),
        "universalcontrol": Entry(.system, "Universal Control", "Klavye/fareyi Mac ve iPad arasında paylaşır."),
        "nsurlsessiond": Entry(.system, "Arka Plan İndirmeleri", "Uygulamaların arka plan indirme ve yüklemelerini yürütür."),
        "softwareupdated": Entry(.system, "Yazılım Güncelleme", "macOS güncellemelerini denetler ve indirir."),
        "mobileassetd": Entry(.system, "Sistem Varlıkları", "Sözlük, ses, yazı tipi, AI modeli gibi indirilebilir sistem dosyalarını yönetir."),
        "suggestd": Entry(.system, "Siri Önerileri", "Mail ve Mesajlar'dan kişi/etkinlik önerileri çıkarır."),
        "assistantd": Entry(.system, "Siri", "Siri isteklerini işler."),
        "siriactionsd": Entry(.system, "Siri Eylemleri", "Siri ve Kestirmeler için uygulama eylemlerini yönetir."),
        "intelligenceplatformd": Entry(.system, "Apple Intelligence", "Apple Intelligence için kişisel bağlamı indeksler."),
        "duetexpertd": Entry(.system, "Akıllı Öneriler", "Kullanım alışkanlıklarınıza göre uygulama/eylem önerileri üretir."),
        "routined": Entry(.system, "Konum Geçmişi", "Önemli konumları ve rutinleri öğrenir (öneriler için)."),
        "linkd": Entry(.system, "App Intents", "Uygulamaların Siri/Kestirmeler'e sunduğu eylemleri indeksler."),
        "dasd": Entry(.system, "Görev Zamanlayıcı", "Arka plan işlerini enerji ve kullanım durumuna göre zamanlar."),
        "coreduetd": Entry(.system, "coreduetd", "Kullanım istatistiklerini toplayarak sistem zamanlamasına yardım eder."),
        "symptomsd": Entry(.system, "Ağ Teşhisi", "Ağ sorunlarını izler ve teşhis eder."),
        "usernoted": Entry(.system, "Bildirim Servisi", "Uygulama bildirimlerini toplar ve iletir."),
        "identityservicesd": Entry(.system, "iMessage / FaceTime", "iMessage ve FaceTime kimlik servisleri."),
        "imagent": Entry(.system, "Mesajlar Ajanı", "iMessage mesajlarını arka planda alır."),
        "calendaragent": Entry(.system, "Takvim Ajanı", "Takvim hesaplarını senkronize eder."),
        "contactsd": Entry(.system, "Kişiler", "Kişiler veritabanını yönetir."),
        "accountsd": Entry(.system, "Hesaplar", "İnternet hesaplarını (iCloud, Google vb.) yönetir."),
        "akd": Entry(.system, "Apple Kimliği", "Apple Hesabı kimlik doğrulaması."),
        "iconservicesagent": Entry(.system, "Simge Servisi", "Uygulama ve dosya simgelerini oluşturup önbelleğe alır."),
        "applespell": Entry(.system, "Yazım Denetimi", "Sistem genelinde yazım denetimi ve otomatik düzeltme."),
        "studentd": Entry(.system, "Sınıf (Classroom)", "Apple Classroom / okul yönetimi servisi."),
        "quicklookuiservice": Entry(.system, "Hızlı Bakış", "Boşluk tuşuyla dosya önizleme."),
        "wallpaperagent": Entry(.system, "Duvar Kağıdı", "Masaüstü duvar kağıdını yönetir.", tip: "Hareketli (Aerial) duvar kağıtları bellek ve GPU kullanır; statik seçmek tasarruf sağlar."),
        "wallpaperaerialsextension": Entry(.system, "Hareketli Duvar Kağıdı", "Hareketli (Aerial) duvar kağıdı/ekran koruyucusu oynatır.", tip: "Statik bir duvar kağıdına geçerek bu belleği kazanabilirsiniz."),
        "viewbridgeauxiliary": Entry(.system, "ViewBridge", "Uygulamaların başka süreçlerin arayüzlerini göstermesini sağlar."),
        "themewidgetcontrolviewservice": Entry(.system, "Tema Widget Servisi", "Sistem Ayarları'nın görünüm/tema bölümüne ait arayüz servisi."),
        "sysmond": Entry(.system, "sysmond", "Etkinlik Monitörü'ne süreç verisi sağlar."),

        // Kullanıcı uygulamaları
        "memscope": Entry(.app, "MemScope", "Şu an kullandığınız bellek yöneticisi."),
        "activity monitor": Entry(.app, "Etkinlik Monitörü", "Apple'ın sistem izleme uygulaması."),
        "system settings": Entry(.app, "Sistem Ayarları", "macOS ayar uygulaması. İşiniz bittiyse kapatabilirsiniz."),
        "google chrome": Entry(.app, "Google Chrome", "Google'ın web tarayıcısı. Her sekme ve eklenti ayrı bir süreçtir; bellek sekme sayısıyla hızla artar.", tip: "Ayarlar → Performans → Bellek Tasarrufu'nu açın ve kullanmadığınız sekmeleri kapatın."),
        "safari": Entry(.app, "Safari", "Apple'ın web tarayıcısı. Sekme içerikleri 'Web İçeriği' süreçleri olarak buraya dahil edilir.", tip: "Safari arka plan sekmelerini askıya alır; yine de sekme sayısını azaltmak yardımcı olur."),
        "firefox": Entry(.app, "Firefox", "Mozilla'nın web tarayıcısı.", tip: "about:memory sayfasından 'Minimize memory usage' ile bellek boşaltabilirsiniz."),
        "arc": Entry(.app, "Arc", "Chromium tabanlı web tarayıcısı.", tip: "Ayarlardan kullanılmayan sekmelerin otomatik arşivlenmesini kısaltın."),
        "microsoft edge": Entry(.app, "Microsoft Edge", "Chromium tabanlı web tarayıcısı.", tip: "Ayarlar → Sistem ve Performans → Uyku Sekmeleri'ni açın."),
        "brave browser": Entry(.app, "Brave", "Chromium tabanlı web tarayıcısı."),
        "claude": Entry(.app, "Claude", "Anthropic'in Claude uygulaması (veya Claude Code). Electron tabanlıdır; yardımcı süreçleri ve MCP sunucularıyla birlikte 1–2 GB kullanabilir."),
        "chatgpt": Entry(.app, "ChatGPT", "OpenAI'ın masaüstü uygulaması."),
        "grok bot": Entry(.app, "Grok Bot", "Electron tabanlı bir sohbet/yapay zekâ uygulaması.", tip: "Kullanmadığınızda kapatın; Electron uygulamaları boştayken bile yüzlerce MB tutar."),
        "slack": Entry(.app, "Slack", "Ekip mesajlaşma uygulaması (Electron). 500 MB–1.5 GB kullanması yaygındır.", tip: "Kullanmadığınız çalışma alanlarından çıkış yapmak belleği azaltır."),
        "discord": Entry(.app, "Discord", "Sesli/yazılı sohbet uygulaması (Electron)."),
        "spotify": Entry(.app, "Spotify", "Müzik uygulaması.", tip: "Ayarlardan önbellek boyutunu sınırlayabilirsiniz."),
        "whatsapp": Entry(.app, "WhatsApp", "Mesajlaşma uygulaması."),
        "telegram": Entry(.app, "Telegram", "Mesajlaşma uygulaması."),
        "zoom.us": Entry(.app, "Zoom", "Görüntülü toplantı uygulaması. Toplantı yoksa kapatabilirsiniz."),
        "microsoft teams": Entry(.app, "Microsoft Teams", "Toplantı ve sohbet uygulaması. Genellikle çok bellek kullanır."),
        "notion": Entry(.app, "Notion", "Not ve doküman uygulaması (Electron)."),
        "figma": Entry(.app, "Figma", "Tasarım aracı. Büyük dosyalar birkaç GB kullanabilir."),
        "obsidian": Entry(.app, "Obsidian", "Markdown not uygulaması (Electron)."),
        "docker": Entry(.app, "Docker Desktop", "Konteynerleri bir Linux sanal makinesinde çalıştırır. Sanal makineye ayrılan belleği sürekli tutar.", tip: "Settings → Resources → Memory'den sınırı düşürün; kullanmadığınızda Docker'ı kapatın."),
        "orbstack": Entry(.app, "OrbStack", "Hafif Docker/Linux sanal makine aracı. Belleği dinamik kullanır."),
        "visual studio code": Entry(.app, "VS Code", "Kod editörü. Eklentiler ve dil sunucuları ayrı süreçlerde çalışır.", tip: "Kullanmadığınız eklentileri devre dışı bırakmak belleği belirgin düşürür."),
        "code": Entry(.app, "VS Code", "Kod editörü."),
        "cursor": Entry(.app, "Cursor", "Yapay zekâ destekli kod editörü (VS Code tabanlı)."),
        "xcode": Entry(.app, "Xcode", "Apple'ın geliştirme ortamı. Derleme ve indeksleme sırasında çok bellek kullanır.", tip: "Simülatörleri kullanmıyorsanız kapatın."),
        "simulator": Entry(.app, "iOS Simülatörü", "iPhone/iPad simülatörü. Her açık cihaz ayrı bellek kullanır."),
        "android studio": Entry(.app, "Android Studio", "Android geliştirme ortamı. Gradle ve emülatörle birlikte çok bellek kullanır."),
        "warp": Entry(.app, "Warp", "Terminal uygulaması. İçinde çalıştırdığınız komutlar ayrı süreçler olarak listelenir."),
        "iterm2": Entry(.app, "iTerm2", "Terminal uygulaması."),
        "terminal": Entry(.app, "Terminal", "macOS terminali."),
        "blender": Entry(.app, "Blender", "3B modelleme ve render uygulaması. Sahne boyutuna göre çok bellek kullanabilir."),
        "steam": Entry(.app, "Steam", "Oyun platformu. Arka planda çalışmaya devam eder.", tip: "Oyun oynamıyorsanız tamamen kapatın."),
        "postman": Entry(.app, "Postman", "API test aracı (Electron)."),
        "mail": Entry(.app, "Mail", "Apple Mail. Büyük posta kutuları bellek kullanır."),
        "music": Entry(.app, "Müzik", "Apple Music uygulaması."),
        "photos": Entry(.app, "Fotoğraflar", "Apple Fotoğraflar uygulaması."),
        "preview": Entry(.app, "Önizleme", "PDF ve görsel görüntüleyici."),
        "creative cloud": Entry(.app, "Adobe Creative Cloud", "Adobe uygulama yöneticisi.", tip: "Arka planda birçok yardımcı çalıştırır; Adobe uygulaması kullanmıyorsanız kapatın."),
        "dropbox": Entry(.app, "Dropbox", "Bulut dosya senkronizasyonu."),
        "google drive": Entry(.app, "Google Drive", "Bulut dosya senkronizasyonu."),
        "onedrive": Entry(.app, "OneDrive", "Microsoft bulut dosya senkronizasyonu."),

        // Geliştirici
        "node": Entry(.developer, "Node.js", "JavaScript çalıştırıcısı. Bir geliştirme sunucusu, araç veya MCP sunucusu olabilir.", tip: "Hangi komutun başlattığını görmek için süreç detayına bakın."),
        "python": Entry(.developer, "Python", "Bir Python betiği veya uygulaması.", tip: "Jupyter, ML modeli veya veri işleme betikleri çok bellek kullanabilir."),
        "python3": Entry(.developer, "Python", "Bir Python betiği veya uygulaması."),
        "java": Entry(.developer, "Java", "Java uygulaması (Gradle, IDE, sunucu vb.)."),
        "ruby": Entry(.developer, "Ruby", "Bir Ruby betiği veya sunucusu."),
        "ollama": Entry(.developer, "Ollama", "Yerel yapay zekâ modellerini çalıştırır. Yüklü model kadar RAM kullanır (7B ≈ 5 GB).", tip: "Kullanmadığınız modeller `ollama stop <model>` ile bellekten çıkarılabilir."),
        "qemu-system-aarch64": Entry(.developer, "QEMU Sanal Makine", "Bir sanal makine. Ayrılan belleği tutar."),
        "com.docker.backend": Entry(.developer, "Docker Backend", "Docker Desktop'ın arka uç servisi."),
        "postgres": Entry(.developer, "PostgreSQL", "Veritabanı sunucusu."),
        "redis-server": Entry(.developer, "Redis", "Bellek içi veritabanı sunucusu."),
        "mongod": Entry(.developer, "MongoDB", "Veritabanı sunucusu."),
    ]
}
