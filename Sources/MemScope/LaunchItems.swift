import Foundation

/// Oturum açılışında veya sistem başlangıcında otomatik çalışan üçüncü taraf ajanlar (LaunchAgents/Daemons).
struct LaunchItem: Identifiable, Hashable, Sendable {
    enum Scope: String, Sendable {
        case userAgent = "Kullanıcı ajanı"
        case systemAgent = "Tüm kullanıcılar"
        case daemon = "Sistem servisi"
    }

    let id: String          // plist yolu
    let label: String
    let program: String?
    let scope: Scope
    let runAtLoad: Bool
    let keepAlive: Bool
    let disabled: Bool

    var plistPath: String { id }

    /// "com.google.keystone.agent" → "Google"
    var vendor: String {
        let parts = label.split(separator: ".")
        guard parts.count >= 2 else { return label }
        let v = ["com", "org", "net", "io", "jp", "co", "de", "dev", "ai", "app", "me", "us", "uk", "fr", "tr"].contains(String(parts[0])) ? parts[1] : parts[0]
        if v == "co", parts.count > 2 { return String(parts[2]).capitalized }
        return String(v).capitalized
    }

    var displayName: String {
        if let program { return (program as NSString).lastPathComponent }
        return label
    }
}

enum LaunchItems {
    static func scan() -> [LaunchItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirs: [(String, LaunchItem.Scope)] = [
            (home + "/Library/LaunchAgents", .userAgent),
            ("/Library/LaunchAgents", .systemAgent),
            ("/Library/LaunchDaemons", .daemon),
        ]
        var items: [LaunchItem] = []
        for (dir, scope) in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for f in files where f.hasSuffix(".plist") {
                let path = dir + "/" + f
                guard let data = FileManager.default.contents(atPath: path),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
                let label = plist["Label"] as? String ?? (f as NSString).deletingPathExtension
                let program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first
                let keepAlive: Bool = {
                    if let b = plist["KeepAlive"] as? Bool { return b }
                    return plist["KeepAlive"] is [String: Any]
                }()
                items.append(LaunchItem(id: path, label: label, program: program, scope: scope,
                                        runAtLoad: plist["RunAtLoad"] as? Bool ?? false,
                                        keepAlive: keepAlive,
                                        disabled: plist["Disabled"] as? Bool ?? false))
            }
        }
        return items.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }
}
