import SwiftUI

/// Desenha uma figura do motor num Canvas (um único passe de desenho, sem SVG nem WebView).
/// As coordenadas seguem a caixa 0–100 do app original.
struct PsicoFigure: View, Equatable {
    let fig: PFFig

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 100
            ctx.translateBy(x: (size.width - 100 * s) / 2, y: (size.height - 100 * s) / 2)
            ctx.scaleBy(x: s, y: s)
            PsicoDraw.draw(fig, in: &ctx)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Preferências de desenho das figuras (só aparência; não mudam a geração das questões).
enum PsicoDisplay {
    static let emphasizeSizeKey = "pf.emphasizeSize"
    static var emphasizeSize: Bool { UserDefaults.standard.object(forKey: emphasizeSizeKey) as? Bool ?? true }
}

enum PsicoDraw {
    static let sides: [String: Int] = ["triangle": 3, "square": 4, "pentagon": 5, "hexagon": 6]

    static let layout: [Int: [CGPoint]] = {
        func p(_ a: [[CGFloat]]) -> [CGPoint] { a.map { CGPoint(x: $0[0], y: $0[1]) } }
        return [
            1: p([[50, 50]]), 2: p([[30, 50], [70, 50]]), 3: p([[50, 30], [30, 68], [70, 68]]),
            4: p([[32, 32], [68, 32], [32, 68], [68, 68]]), 5: p([[30, 30], [70, 30], [50, 50], [30, 70], [70, 70]]),
            6: p([[30, 25], [70, 25], [30, 50], [70, 50], [30, 75], [70, 75]]),
            7: p([[25, 25], [50, 25], [75, 25], [50, 50], [25, 75], [50, 75], [75, 75]]),
            8: p([[25, 25], [50, 25], [75, 25], [37, 50], [63, 50], [25, 75], [50, 75], [75, 75]]),
            9: p([[25, 25], [50, 25], [75, 25], [25, 50], [50, 50], [75, 50], [25, 75], [50, 75], [75, 75]]),
        ]
    }()
    static let baseR: [Int: CGFloat] = [1: 30, 2: 17, 3: 16, 4: 15, 5: 12, 6: 11, 7: 10, 8: 10, 9: 10]
    /// Escala de cada tamanho (pequeno, médio, grande). Só muda o desenho, nunca a questão.
    /// "Realçar diferença de tamanho" (padrão) separa mais os três tamanhos na tela do celular.
    static var sizeF: [CGFloat] { PsicoDisplay.emphasizeSize ? [0.42, 0.70, 1] : [0.55, 0.78, 1] }
    static let lineSeg: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (50, 8, 50, 92), (8, 50, 92, 50), (14, 14, 86, 86), (86, 14, 14, 86), (14, 14, 86, 14), (14, 86, 86, 86),
    ]

    private static let shapeCache: [String: [CGPoint]] = {
        var d: [String: [CGPoint]] = [:]
        for t in ["triangle", "square", "pentagon", "hexagon", "star", "cross", "arrow", "half", "flag"] { d[t] = makePoints(t) }
        return d
    }()

    static func points(_ type: String) -> [CGPoint] { shapeCache[type] ?? [] }

    private static func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    private static func unit(_ deg: Double, _ r: Double = 1, dy: Double = 0) -> CGPoint {
        let a: Double = deg * Double.pi / 180
        return CGPoint(x: r * cos(a), y: r * sin(a) + dy)
    }

    private static func makePoints(_ type: String) -> [CGPoint] {
        var pts: [CGPoint] = []
        if let n = sides[type] {
            let off: Double = n % 2 == 1 ? 0 : 180 / Double(n)
            let step: Double = 360 / Double(n)
            for i in 0..<n {
                let deg: Double = -90 + off + Double(i) * step
                pts.append(unit(deg))
            }
            return pts
        }
        switch type {
        case "star":
            for i in 0..<10 {
                let r: Double = i % 2 == 1 ? 0.45 : 1
                pts.append(unit(-90 + Double(i) * 36, r))
            }
        case "cross":
            let t: Double = 0.34
            pts = [pt(-t, -1), pt(t, -1), pt(t, -t), pt(1, -t), pt(1, t), pt(t, t),
                   pt(t, 1), pt(-t, 1), pt(-t, t), pt(-1, t), pt(-1, -t), pt(-t, -t)]
        case "arrow":
            pts = [pt(0, -1), pt(0.75, -0.1), pt(0.3, -0.1), pt(0.3, 1), pt(-0.3, 1), pt(-0.3, -0.1), pt(-0.75, -0.1)]
        case "half":
            for i in 0..<17 {
                pts.append(unit(180 + 180 * Double(i) / 16, dy: 0.45))
            }
        case "flag":
            pts = [pt(-0.65, 1), pt(-0.65, -1), pt(0.85, -0.55), pt(-0.38, -0.1), pt(-0.38, 1)]
        default:
            break
        }
        return pts
    }

    static func fillColor(_ f: Int) -> Color { f == 2 ? PF.ink : f == 1 ? PF.gray : PF.cell }

    static func shapePath(_ type: String, _ c: CGPoint, _ r: CGFloat, _ rotDeg: Double) -> Path {
        if type == "circle" {
            let rr = r * 0.92
            return Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr))
        }
        let a: Double = rotDeg * Double.pi / 180, ca = CGFloat(cos(a)), sa = CGFloat(sin(a))
        var path = Path()
        let pts = points(type).map { p in CGPoint(x: c.x + r * (p.x * ca - p.y * sa), y: c.y + r * (p.x * sa + p.y * ca)) }
        guard let first = pts.first else { return path }
        path.move(to: first)
        for p in pts.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }

    static func shape(_ ctx: inout GraphicsContext, _ type: String, _ c: CGPoint, _ r: CGFloat, _ rotDeg: Double, fill: Int) {
        let p = shapePath(type, c, r, rotDeg)
        ctx.fill(p, with: .color(fillColor(fill)))
        ctx.stroke(p, with: .color(PF.ink), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
    }

    static func dot(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(PF.ink))
    }

    static func draw(_ f: PFFig, in ctx: inout GraphicsContext) {
        switch f.k {
        case "panel": if let p = f.p { panel(p, compact: f.compact ?? false, &ctx) }
        case "poly": poly(f.cs ?? [], &ctx)
        default: intruder(f, &ctx)
        }
    }

    static func panel(_ p: PFPanel, compact: Bool, _ ctx: inout GraphicsContext) {
        for b in 0..<6 where p.lines & (1 << b) != 0 {
            let l = lineSeg[b]
            var path = Path(); path.move(to: CGPoint(x: l.0, y: l.1)); path.addLine(to: CGPoint(x: l.2, y: l.3))
            ctx.stroke(path, with: .color(PF.ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        if let g = p.ghost, g != 0 {
            for b in 0..<6 where g & (1 << b) != 0 {
                let l = lineSeg[b]
                var path = Path(); path.move(to: CGPoint(x: l.0, y: l.1)); path.addLine(to: CGPoint(x: l.2, y: l.3))
                ctx.stroke(path, with: .color(PF.muted), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [5, 4]))
            }
        }
        guard p.count > 0 else { return }
        let k: CGFloat = (compact ? 0.78 : 1) * (p.lines != 0 ? 0.6 : 1)
        let lay = layout[p.count] ?? layout[1]!
        let r = (baseR[p.count] ?? 30) * sizeF[max(0, min(2, p.size))] * k
        let spread: CGFloat = compact ? 0.8 : 1
        for pt in lay {
            let c = CGPoint(x: 50 + (pt.x - 50) * spread, y: 50 + (pt.y - 50) * spread)
            shape(&ctx, p.shape, c, r, Double(p.rot * 45), fill: p.fill)
        }
        if p.mark >= 0 {
            let a: Double = (-90 + Double(p.mark) * 45) * Double.pi / 180
            dot(&ctx, CGPoint(x: 50 + 43 * cos(a), y: 50 + 43 * sin(a)), 5)
        }
    }

    static func poly(_ cs: [PFCell], _ ctx: inout GraphicsContext) {
        guard !cs.isEmpty else { return }
        let mx = cs.map(\.x).min()!, my = cs.map(\.y).min()!
        let w = CGFloat(cs.map(\.x).max()! - mx + 1), h = CGFloat(cs.map(\.y).max()! - my + 1)
        let u = min(80 / w, 80 / h, 20)
        let ox = 50 - w * u / 2, oy = 50 - h * u / 2
        for c in cs {
            let rect = Path(CGRect(x: ox + CGFloat(c.x - mx) * u, y: oy + CGFloat(c.y - my) * u, width: u, height: u))
            ctx.fill(rect, with: .color((c.m ?? 0) != 0 ? PF.ink : PF.cell))
            ctx.stroke(rect, with: .color(PF.ink), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
        }
    }

    static func intruder(_ f: PFFig, _ ctx: inout GraphicsContext) {
        let shapeName = f.shape ?? "circle"
        let tri = shapeName == "triangle"
        if f.t == "lados" {
            shape(&ctx, shapeName, CGPoint(x: 50, y: tri ? 56 : 50), tri ? 42 : 38, Double((f.rot ?? 0) * 45), fill: f.fill ?? 0)
            let lay = layout[f.n ?? 1] ?? layout[1]!
            let cy: CGFloat = tri ? 60 : 50
            for pt in lay { dot(&ctx, CGPoint(x: 50 + (pt.x - 50) * 0.4, y: cy + (pt.y - 50) * 0.4), 3.6) }
        } else {
            shape(&ctx, shapeName, CGPoint(x: 50, y: 50), 40, 0, fill: 0)
            shape(&ctx, f.inner ?? "circle", CGPoint(x: 50, y: tri ? 57 : 50), 15, 0, fill: f.fill ?? 0)
        }
    }
}
