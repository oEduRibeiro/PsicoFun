import SwiftUI
import UIKit

/// Paleta do app original: papel branco e tinta grafite; vermelho só para ação e erro; verde só para acerto.
enum PF {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    static let bg = dyn(0xEEF0F2, 0x0F1114)
    static let paper = dyn(0xFFFFFF, 0x191C21)
    static let cell = dyn(0xFFFFFF, 0x1F2329)
    static let ink = dyn(0x15171B, 0xECEAE4)
    static let muted = dyn(0x5B616B, 0x9AA1AB)
    static let line = dyn(0xD6D9DE, 0x2E333B)
    static let acc = dyn(0xC8102E, 0xFF5C63)
    static let ok = dyn(0x127A3A, 0x4ADE80)
    static let okBg = dyn(0xE3F4E8, 0x143222)
    static let bad = dyn(0xC8102E, 0xFF6B70)
    static let badBg = dyn(0xFBE6E8, 0x3A1A1D)
    static let gray = dyn(0xA1A7B0, 0x6B727C)
    static let soft = dyn(0xF5F6F8, 0x22262C)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Componentes

/// Cartão branco com borda fina (seções das telas).
struct PFCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PF.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PF.line, lineWidth: 1))
    }
}

/// Botões no estilo do app: primário (tinta), ação (vermelho), fantasma e perigo.
struct PFButtonStyle: ButtonStyle {
    enum Kind { case primary, accent, ghost, danger }
    var kind: Kind = .primary
    var small = false
    var wide = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fg: Color, bg: Color, border: Color
        switch kind {
        case .primary: fg = PF.paper; bg = PF.ink; border = PF.ink
        case .accent: fg = .white; bg = PF.acc; border = PF.acc
        case .ghost: fg = PF.ink; bg = .clear; border = PF.line
        case .danger: fg = PF.bad; bg = .clear; border = PF.bad
        }
        return configuration.label
            .font(.system(size: small ? 14 : (wide ? 17 : 16), weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, small ? 12 : 16)
            .frame(minHeight: small ? 36 : (wide ? 52 : 46))
            .frame(maxWidth: wide ? .infinity : nil)
            .background(bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(border, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Toque com leve encolhimento (cartões, alternativas).
struct PFPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Chip de escolha (tipos de questão, quantidade, tempo).
struct PFChip: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(on ? PF.paper : PF.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(on ? PF.ink : PF.paper, in: Capsule())
                .overlay(Capsule().stroke(on ? PF.ink : PF.line, lineWidth: 1.5))
        }
        .buttonStyle(PFPressStyle())
    }
}

/// Barras horizontais (rótulo, barra, valor).
struct PFBars: View {
    struct Row: Identifiable {
        let id: String
        let label: String
        let pct: Double
        let value: String
        var accent = false
    }
    let rows: [Row]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.label).font(.system(size: 14))
                        Spacer(minLength: 8)
                        Text(r.value).font(.system(size: 14).monospacedDigit()).foregroundColor(PF.muted)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(PF.soft)
                            Capsule().fill(r.accent ? PF.acc : PF.ink)
                                .frame(width: max(4, g.size.width * min(1, max(0.02, r.pct / 100))))
                        }
                    }
                    .frame(height: 10)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Grade de pares rótulo/valor.
struct PFKeyValues: View {
    let items: [(String, String)]
    var big = false

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16, alignment: .leading)], alignment: .leading, spacing: 10) {
            ForEach(items.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 1) {
                    Text(items[i].0).font(.system(size: 13)).foregroundColor(PF.muted)
                    Text(items[i].1).font(.system(size: big ? 24 : 17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
    }
}

/// Layout em fluxo (chips que quebram linha). iOS 16+.
struct PFFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowH = max(rowH, s.height)
        }
        return CGSize(width: min(width, maxX), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

/// Ícone de olho (aberto/riscado) usado para "resposta escondida".
struct PFEye: View {
    let open: Bool
    var body: some View { Image(systemName: open ? "eye" : "eye.slash") }
}
