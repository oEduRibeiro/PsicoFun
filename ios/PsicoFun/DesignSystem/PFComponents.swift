import SwiftUI

// MARK: - Tons semânticos

/// Tom de um selo, aviso ou bloco de número.
enum PFTone {
    case neutral, ink, accent, ok, bad, warn, pulse

    var fg: Color {
        switch self {
        case .neutral: return PF.muted
        case .ink: return PF.paper
        case .accent: return PF.acc
        case .ok: return PF.ok
        case .bad: return PF.bad
        case .warn: return PF.warn
        case .pulse: return PF.pulse
        }
    }

    var bg: Color {
        switch self {
        case .neutral: return PF.soft
        case .ink: return PF.ink
        case .accent: return PF.accBg
        case .ok: return PF.okBg
        case .bad: return PF.badBg
        case .warn: return PF.warnBg
        case .pulse: return PF.pulseBg
        }
    }

    /// Cor do valor em blocos de número.
    var value: Color {
        switch self {
        case .neutral, .ink: return PF.ink
        default: return fg
        }
    }
}

// MARK: - Estrutura de tela

/// Tela padrão: rolagem, fundo do app, margens e largura máxima.
struct PFScreen<Content: View>: View {
    var spacing: CGFloat = PF.Space.l
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content }
                .padding(.horizontal, PF.Space.screen)
                .padding(.top, PF.Space.s)
                .padding(.bottom, PF.Space.xxl)
                .frame(maxWidth: PF.Space.maxWidth)
                .frame(maxWidth: .infinity)
        }
        .background(PF.bg.ignoresSafeArea())
    }
}

/// Cartão: papel com borda fina. Base de todas as seções.
struct PFCard<Content: View>: View {
    var padding: CGFloat = 18
    var spacing: CGFloat = PF.Space.m
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PF.paper, in: RoundedRectangle(cornerRadius: PF.Radius.l, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PF.Radius.l, style: .continuous).stroke(PF.line, lineWidth: 1))
    }
}

/// Título de cartão, com subtítulo e ícone opcionais.
struct PFCardHeader: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var tone: PFTone = .neutral

    init(_ title: String, subtitle: String? = nil, icon: String? = nil, tone: PFTone = .neutral) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tone = tone
    }

    var body: some View {
        HStack(alignment: .top, spacing: PF.Space.m) {
            if let icon = icon {
                PFIconBadge(icon: icon, tone: tone)
            }
            VStack(alignment: .leading, spacing: PF.Space.xxs) {
                Text(title).pfText(.title).foregroundColor(PF.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let s = subtitle {
                    Text(s).pfText(.footnote).foregroundColor(PF.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Rótulo de grupo fora dos cartões ("Escolha um modo", "Sessões").
struct PFEyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .pfText(.eyebrow)
            .foregroundColor(PF.muted)
            .padding(.horizontal, PF.Space.xs)
            .padding(.top, PF.Space.s)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Ícone dentro de um quadrado arredondado colorido.
struct PFIconBadge: View {
    let icon: String
    var tone: PFTone = .neutral
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundColor(tone == .neutral ? PF.ink : tone.fg)
            .frame(width: size, height: size)
            .background(tone.bg, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Divisória fina.
struct PFDivider: View {
    var body: some View { Rectangle().fill(PF.line).frame(height: 1) }
}

// MARK: - Números

/// Bloco de número: rótulo, valor e unidade.
struct PFStatTile: View {
    let label: String
    let value: String
    var unit: String? = nil
    var tone: PFTone = .neutral
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: PF.Space.xs) {
            Text(label).pfText(.eyebrow).foregroundColor(PF.muted).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .pfText(large ? .display : .metric)
                    .foregroundColor(tone.value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let u = unit {
                    Text(u).pfText(.caption).foregroundColor(PF.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(unit.map { "\(value) \($0)" } ?? value)
    }
}

/// Linha de blocos de número separados por divisórias verticais.
struct PFStatRow: View {
    let items: [PFStatTile]

    var body: some View {
        HStack(alignment: .top, spacing: PF.Space.m) {
            ForEach(items.indices, id: \.self) { i in
                if i > 0 { Rectangle().fill(PF.line).frame(width: 1).padding(.vertical, 2) }
                items[i]
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Selos e avisos

/// Selo em cápsula ("Teste", "parcial", "Acertou").
struct PFBadge: View {
    let text: String
    var tone: PFTone = .neutral
    var icon: String? = nil

    init(_ text: String, tone: PFTone = .neutral, icon: String? = nil) {
        self.text = text
        self.tone = tone
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon { Image(systemName: icon).imageScale(.small) }
            Text(text)
        }
        .pfText(.caption, weight: .bold)
        .foregroundColor(tone.fg)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(tone.bg, in: Capsule())
    }
}

/// Aviso em caixa (informação, alerta).
struct PFNote: View {
    let text: String
    var icon: String = "info.circle"
    var tone: PFTone = .neutral

    var body: some View {
        HStack(alignment: .top, spacing: PF.Space.s) {
            Image(systemName: icon).foregroundColor(tone == .neutral ? PF.muted : tone.fg)
                .accessibilityHidden(true)
            Text(text).pfText(.footnote).foregroundColor(tone == .neutral ? PF.muted : PF.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(PF.Space.m)
        .background(tone.bg, in: RoundedRectangle(cornerRadius: PF.Radius.s, style: .continuous))
    }
}

/// Estado vazio: ícone, título, explicação e ação opcional.
struct PFEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: PF.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(PF.gray)
                .frame(width: 64, height: 64)
                .background(PF.soft, in: Circle())
                .accessibilityHidden(true)
            Text(title).pfText(.headline).foregroundColor(PF.ink).multilineTextAlignment(.center)
            Text(message).pfText(.footnote).foregroundColor(PF.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let t = actionTitle, let a = action {
                Button(t, action: a).buttonStyle(PFButtonStyle(kind: .primary, small: true))
                    .padding(.top, PF.Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PF.Space.l)
        .padding(.horizontal, PF.Space.s)
    }
}

// MARK: - Linhas

/// Linha de lista: ícone, título, subtítulo, valor e seta.
struct PFRow: View {
    var icon: String? = nil
    var tone: PFTone = .neutral
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var chevron = false

    var body: some View {
        HStack(spacing: PF.Space.m) {
            if let icon = icon { PFIconBadge(icon: icon, tone: tone, size: 30) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).pfText(.body).foregroundColor(tone == .bad ? PF.bad : PF.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let s = subtitle {
                    Text(s).pfText(.footnote).foregroundColor(PF.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: PF.Space.s)
            if let v = value {
                Text(v).pfText(.metricSmall, weight: .regular).foregroundColor(PF.muted).multilineTextAlignment(.trailing)
            }
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(PF.gray)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Interruptor com ícone, título e explicação.
struct PFToggleRow: View {
    var icon: String? = nil
    var tone: PFTone = .neutral
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: PF.Space.m) {
                if let icon = icon { PFIconBadge(icon: icon, tone: tone, size: 30) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).pfText(.body).foregroundColor(PF.ink)
                    if let s = subtitle {
                        Text(s).pfText(.footnote).foregroundColor(PF.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .tint(PF.ok)
        .frame(minHeight: 44)
    }
}

// MARK: - Controles

/// Botões: primário (tinta), ação (vermelho), fantasma e perigo.
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
        let glass = PFGlass.available
        let shape = RoundedRectangle(cornerRadius: glass ? 22 : PF.Radius.button, style: .continuous)
        let tint: Color? = kind == .primary ? PF.ink : kind == .accent ? PF.acc : nil
        let minH: CGFloat = small ? 36 : (wide ? 54 : 46)
        return configuration.label
            .pfText(small ? .footnote : .headline, weight: .semibold)
            .foregroundColor(fg)
            .multilineTextAlignment(.center)
            .padding(.horizontal, small ? 12 : 18)
            .padding(.vertical, small ? 6 : 10)
            .frame(minHeight: minH)
            .frame(maxWidth: wide ? .infinity : nil)
            .pfGlass(shape, tint: tint, interactive: true, fallback: bg)
            .overlay(shape.stroke(glass && kind != .danger ? Color.clear : border, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(PF.Motion.press, value: configuration.isPressed)
    }
}

/// Toque com leve encolhimento (cartões, alternativas).
struct PFPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(PF.Motion.press, value: configuration.isPressed)
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
                .pfText(.callout, weight: .semibold)
                .foregroundColor(on ? PF.paper : PF.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .pfGlass(Capsule(), tint: on ? PF.ink : nil, interactive: true, fallback: on ? PF.ink : PF.paper)
                .overlay(Capsule().stroke(PFGlass.available ? Color.clear : (on ? PF.ink : PF.line), lineWidth: 1.5))
        }
        .buttonStyle(PFPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Controle segmentado do app (pílula com indicador que desliza).
struct PFSegmented<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        var icon: String? = nil
    }

    let options: [Option]
    @Binding var selection: Value
    var compact = false
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                segment(options[i])
            }
        }
        .padding(3)
        .background(PF.soft, in: Capsule())
        .overlay(Capsule().stroke(PF.line, lineWidth: 1))
    }

    private func segment(_ o: Option) -> some View {
        let on = o.value == selection
        return Button {
            guard !on else { return }
            Haptics.play("selection")
            withAnimation(PF.Motion.spring) { selection = o.value }
        } label: {
            HStack(spacing: 6) {
                if let icon = o.icon { Image(systemName: icon).imageScale(.small) }
                Text(o.title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .pfText(compact ? .footnote : .callout, weight: .semibold)
            .foregroundColor(on ? PF.paper : PF.muted)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: compact ? 32 : 38)
            .background {
                if on {
                    Capsule().fill(PF.ink).matchedGeometryEffect(id: "pf.seg", in: ns)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Dados

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
        VStack(spacing: PF.Space.m) {
            ForEach(rows) { r in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.label).pfText(.footnote).foregroundColor(PF.ink)
                        Spacer(minLength: 8)
                        Text(r.value).pfText(.footnote).monospacedDigit().foregroundColor(PF.muted)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(PF.soft)
                            Capsule().fill(r.accent ? PF.acc : PF.ink)
                                .frame(width: max(4, g.size.width * min(1, max(0.02, r.pct / 100))))
                        }
                    }
                    .frame(height: 8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(r.label)
                .accessibilityValue(r.value)
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16, alignment: .leading)], alignment: .leading, spacing: 14) {
            ForEach(items.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 3) {
                    Text(items[i].0).pfText(.eyebrow).foregroundColor(PF.muted)
                    Text(items[i].1).pfText(big ? .metric : .metricSmall, weight: .bold).foregroundColor(PF.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .combine)
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
