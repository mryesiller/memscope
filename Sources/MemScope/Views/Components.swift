import SwiftUI
import AppKit

enum Theme {
    static let app = Color(red: 0.36, green: 0.58, blue: 1.0)
    static let wired = Color(red: 1.0, green: 0.62, blue: 0.28)
    static let compressed = Color(red: 0.82, green: 0.42, blue: 0.98)
    static let cached = Color(red: 0.28, green: 0.82, blue: 0.80)
    static let free = Color.white.opacity(0.10)
    static let swap = Color(red: 1.0, green: 0.42, blue: 0.50)

    static let cardFill = Color.white.opacity(0.045)
    static let cardStroke = Color.white.opacity(0.08)
    static let secondaryText = Color.white.opacity(0.58)

    static let background = LinearGradient(
        colors: [Color(red: 0.055, green: 0.063, blue: 0.10), Color(red: 0.085, green: 0.062, blue: 0.14)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static func pressureColor(_ p: PressureLevel) -> Color {
        switch p {
        case .normal: return Color(red: 0.30, green: 0.88, blue: 0.55)
        case .warning: return Color(red: 1.0, green: 0.80, blue: 0.25)
        case .critical: return Color(red: 1.0, green: 0.35, blue: 0.40)
        }
    }
}

struct Card<Content: View, Accessory: View>: View {
    let title: String
    let icon: String
    var accent: Color = .white
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .background(accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                accessory()
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.cardStroke))
    }
}

extension Card where Accessory == EmptyView {
    init(title: String, icon: String, accent: Color = .white, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, icon: icon, accent: accent, accessory: { EmptyView() }, content: content)
    }
}

struct RingSegment: Equatable {
    let fraction: Double
    let color: Color
}

struct MemoryRing: View {
    let segments: [RingSegment]
    var lineWidth: CGFloat = 22

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.07), lineWidth: lineWidth)
            ForEach(Array(segments.enumerated()), id: \.offset) { i, seg in
                let start = segments.prefix(i).reduce(0) { $0 + $1.fraction }
                Circle()
                    .trim(from: start, to: min(1, start + seg.fraction))
                    .stroke(seg.color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: seg.color.opacity(0.35), radius: 6)
            }
        }
    }
}

struct CategoryBadge: View {
    let category: ProcCategory
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon).font(.system(size: 9, weight: .bold))
            Text(compact ? category.title : "\(category.title) · \(category.verdict)")
                .font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .foregroundStyle(category.color)
        .background(category.color.opacity(0.14), in: Capsule())
    }
}

struct GroupIcon: View {
    @Environment(MemoryStore.self) private var store
    let group: AppGroup
    var size: CGFloat = 28

    var body: some View {
        if let img = store.icon(for: group) {
            Image(nsImage: img).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: group.category.icon)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(group.category.color)
                .frame(width: size, height: size)
                .background(group.category.color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        }
    }
}

struct LegendRow: View {
    let color: Color
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            Text(value).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }
}

struct MeterBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule().fill(color.gradient).frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

struct LiveDot: View {
    var color: Color = .green

    // Sürekli animasyon tüm panelin her karede yeniden yerleşmesine yol açtığı için statik parıltı.
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.9), radius: 4)
    }
}

// MARK: - Uyarlanabilir düzen

/// İçeriğe mevcut genişliği verir. `fixedWidth` verilirse (snapshot) GeometryReader kullanılmaz.
struct WidthReader<Content: View>: View {
    var fixedWidth: CGFloat? = nil
    @ViewBuilder var content: (CGFloat) -> Content

    var body: some View {
        if let fixedWidth {
            content(fixedWidth).frame(width: fixedWidth)
        } else {
            GeometryReader { geo in
                ScrollView { content(geo.size.width).frame(width: geo.size.width) }
            }
        }
    }
}

/// Başlık + sağdaki kontroller. Sığmazsa kontroller başlığın altına iner; başlık asla harf harf kırılmaz.
struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    var titleSize: CGFloat = 28
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                titleBlock
                Spacer(minLength: 12)
                trailing().fixedSize()
            }
            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                trailing().fixedSize()
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: titleSize, weight: .bold, design: .rounded))
                .lineLimit(1).fixedSize()
            Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }
}
