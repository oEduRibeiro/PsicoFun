import SwiftUI
import UIKit

/// Design system do PsicoFun.
///
/// Identidade: folha de prova. Papel claro e tinta grafite; vermelho só para ação e erro;
/// verde só para acerto; âmbar só para aviso; rosa só para frequência cardíaca.
/// Todas as telas (Psicotécnico, Desempenho, Ajustes, Palográfico e o seletor do topo)
/// usam só estes tokens e os componentes de `PFComponents.swift`.
enum PF {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    // MARK: Superfícies
    /// Fundo das telas.
    static let bg = dyn(0xEEF0F2, 0x0F1114)
    /// Cartões e folhas.
    static let paper = dyn(0xFFFFFF, 0x191C21)
    /// Células de figura.
    static let cell = dyn(0xFFFFFF, 0x1F2329)
    /// Preenchimento discreto (trilhos de barra, campos, linhas alternadas).
    static let soft = dyn(0xF5F6F8, 0x22262C)
    /// Bordas finas e divisórias.
    static let line = dyn(0xD6D9DE, 0x2E333B)

    // MARK: Texto
    static let ink = dyn(0x15171B, 0xECEAE4)
    static let muted = dyn(0x5B616B, 0x9AA1AB)
    static let gray = dyn(0xA1A7B0, 0x6B727C)

    // MARK: Semântica
    /// Ação principal e erro.
    static let acc = dyn(0xC8102E, 0xFF5C63)
    static let accBg = dyn(0xFBE6E8, 0x3A1A1D)
    static let ok = dyn(0x127A3A, 0x4ADE80)
    static let okBg = dyn(0xE3F4E8, 0x143222)
    static let bad = dyn(0xC8102E, 0xFF6B70)
    static let badBg = dyn(0xFBE6E8, 0x3A1A1D)
    /// Aviso (valor que destoa, dado parcial).
    static let warn = dyn(0x9A5B00, 0xF5B042)
    static let warnBg = dyn(0xFFF1D6, 0x3A2A10)
    /// Frequência cardíaca (só registro, nunca "bom/ruim").
    static let pulse = dyn(0xB8325A, 0xFF7A9C)
    static let pulseBg = dyn(0xFBE4EC, 0x3A1A26)

    // MARK: Sessão do Palográfico (sempre escura, para não distrair)
    static let stage = Color(UIColor(hex: 0x0C0D10))
    static let stageInk = Color(UIColor(hex: 0xF2F0EA))
    static let stageMuted = Color(UIColor(hex: 0xF2F0EA)).opacity(0.55)
    static let stageLine = Color(UIColor(hex: 0xF2F0EA)).opacity(0.14)

    // MARK: Espaçamento (grade de 4 pt)
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        /// Margem lateral das telas.
        static let screen: CGFloat = 16
        /// Largura máxima do conteúdo (iPad / paisagem).
        static let maxWidth: CGFloat = 760
    }

    // MARK: Raios
    enum Radius {
        static let s: CGFloat = 10
        static let m: CGFloat = 14
        static let l: CGFloat = 20
        static let button: CGFloat = 14
    }

    // MARK: Movimento
    enum Motion {
        static let press = Animation.easeOut(duration: 0.12)
        static let quick = Animation.easeOut(duration: 0.2)
        static let spring = Animation.spring(response: 0.38, dampingFraction: 0.86)
        static let bouncy = Animation.spring(response: 0.32, dampingFraction: 0.6)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Tipografia (acompanha o Tamanho do Texto do iOS)

/// Estilos de texto do app. Todos crescem com o Dynamic Type.
enum PFTextStyle {
    /// Números grandes de resultado (total, placar).
    case display
    /// Título de tela dentro do conteúdo.
    case largeTitle
    /// Título de cartão.
    case title
    /// Destaque dentro de cartão.
    case headline
    case body
    case callout
    /// Texto de apoio.
    case footnote
    case caption
    /// Rótulo curto em caixa alta (sobrescrito de seção, rótulo de número).
    case eyebrow
    /// Número médio (blocos de estatística).
    case metric
    /// Número pequeno (tabelas).
    case metricSmall

    fileprivate var spec: (size: CGFloat, weight: Font.Weight, relative: Font.TextStyle) {
        switch self {
        case .display: return (56, .heavy, .largeTitle)
        case .largeTitle: return (32, .heavy, .largeTitle)
        case .title: return (20, .heavy, .title3)
        case .headline: return (17, .semibold, .headline)
        case .body: return (17, .regular, .body)
        case .callout: return (16, .regular, .callout)
        case .footnote: return (14, .regular, .footnote)
        case .caption: return (13, .medium, .caption)
        case .eyebrow: return (12, .bold, .caption)
        case .metric: return (26, .bold, .title)
        case .metricSmall: return (16, .semibold, .body)
        }
    }

    var isNumeric: Bool {
        switch self {
        case .display, .metric, .metricSmall: return true
        default: return false
        }
    }
}

private struct PFTextModifier: ViewModifier {
    let style: PFTextStyle
    let weight: Font.Weight?
    @ScaledMetric private var size: CGFloat

    init(style: PFTextStyle, weight: Font.Weight?) {
        self.style = style
        self.weight = weight
        let s = style.spec
        _size = ScaledMetric(wrappedValue: s.size, relativeTo: s.relative)
    }

    func body(content: Content) -> some View {
        let w: Font.Weight = weight ?? style.spec.weight
        let font: Font = style.isNumeric
            ? Font.system(size: size, weight: w).monospacedDigit()
            : Font.system(size: size, weight: w)
        return content
            .font(font)
            .tracking(style == .eyebrow ? 0.8 : 0)
            .textCase(style == .eyebrow ? .uppercase : nil)
    }
}

extension View {
    /// Aplica um estilo de texto do design system.
    func pfText(_ style: PFTextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(PFTextModifier(style: style, weight: weight))
    }
}
