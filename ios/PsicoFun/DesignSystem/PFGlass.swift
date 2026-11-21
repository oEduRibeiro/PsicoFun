import SwiftUI

// MARK: - Liquid Glass (iOS 26) com recaída para o visual atual

/// Liquid Glass só existe a partir do iOS 26 (e só compila com o SDK do Xcode 26).
/// Em versões anteriores do iOS, ou com um Xcode mais antigo, usa o preenchimento sólido de antes.
enum PFGlass {
    static var available: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    static func style(tint: Color?, interactive: Bool) -> Glass {
        var g = Glass.regular
        if let t = tint { g = g.tint(t) }
        if interactive { g = g.interactive() }
        return g
    }
    #endif
}

#if compiler(>=6.2)
extension View {
    /// Fundo de vidro (iOS 26) ou cor sólida (antes).
    @ViewBuilder
    func pfGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false, fallback: Color) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(PFGlass.style(tint: tint, interactive: interactive), in: shape)
        } else {
            self.background(fallback, in: shape)
        }
    }
}
#else
extension View {
    /// Fundo sólido (SDK sem Liquid Glass).
    func pfGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false, fallback: Color) -> some View {
        self.background(fallback, in: shape)
    }
}
#endif

extension View {
    /// Fundo sólido que some no iOS 26 (deixa o vidro do sistema aparecer, ex.: folhas).
    @ViewBuilder
    func pfSolidBackgroundBeforeGlass(_ color: Color) -> some View {
        if PFGlass.available { self } else { self.background(color.ignoresSafeArea()) }
    }
}
