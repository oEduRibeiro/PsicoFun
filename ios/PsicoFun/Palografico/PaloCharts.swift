import Charts
import SwiftUI

// MARK: - Rendimento por ciclo

/// Traços por ciclo (barras), com a média da sessão tracejada.
/// Ciclos que destoam (mesma regra da entrada) ficam em âmbar.
struct PaloCycleChart: View {
    let counts: [Int]

    private struct Bar: Identifiable {
        let cycle: Int
        let value: Int
        let outlier: Bool
        var id: Int { cycle }
    }

    var body: some View {
        let outliers: Set<Int> = Set(PaloMetrics.outliers(counts))
        let bars: [Bar] = counts.indices.map { i in
            Bar(cycle: i + 1, value: counts[i], outlier: outliers.contains(i))
        }
        let mean: Double = PaloMetrics(counts: counts).mean
        let top: Int = max(10, counts.max() ?? 0)
        let upper: Double = Double(top) * 1.18
        Chart {
            ForEach(bars) { b in
                barMark(b)
            }
            if counts.count > 1 {
                meanRule(mean)
            }
        }
        .chartYScale(domain: 0.0...upper)
        .chartXAxis {
            AxisMarks { v in
                AxisValueLabel {
                    if let s = v.as(String.self) { Text(s).pfText(.caption).foregroundColor(PF.muted) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(PF.line)
                AxisValueLabel().foregroundStyle(PF.muted)
            }
        }
        .accessibilityLabel("Traços verticais por ciclo")
    }

    @ChartContentBuilder
    private func barMark(_ b: Bar) -> some ChartContent {
        let fill: Color = b.outlier ? PF.warn : PF.ink
        BarMark(x: .value("Ciclo", "C\(b.cycle)"), y: .value("Traços", Double(b.value)), width: .ratio(0.56))
            .cornerRadius(5)
            .foregroundStyle(fill)
            .annotation(position: .top, spacing: 4) {
                Text("\(b.value)").pfText(.caption, weight: .bold).foregroundColor(b.outlier ? PF.warn : PF.ink)
            }
            .accessibilityLabel("Ciclo \(b.cycle)")
            .accessibilityValue(b.outlier ? "\(b.value) traços, destoa dos outros" : "\(b.value) traços")
    }

    @ChartContentBuilder
    private func meanRule(_ mean: Double) -> some ChartContent {
        RuleMark(y: .value("Média", mean))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(PF.acc)
            .annotation(position: .top, alignment: .trailing, spacing: 2) {
                Text("média \(PaloFormat.decimal(mean))")
                    .pfText(.caption, weight: .bold)
                    .foregroundColor(PF.acc)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(PF.paper.opacity(0.9), in: Capsule())
            }
            .accessibilityLabel("Média por ciclo")
            .accessibilityValue(PaloFormat.decimal(mean))
    }
}

// MARK: - Frequência cardíaca por ciclo

/// FC ao longo dos ciclos: faixa mínima–máxima de cada ciclo, linha da média por ciclo,
/// média da sessão e (se houver) média das sessões anteriores. Ciclos parciais ficam em âmbar,
/// ciclos sem leitura aparecem como coluna vazia. Toque num ciclo para ver os números.
struct PaloHRChart: View {
    let cycles: [PaloHRCycle]
    var sessionMean: Double?
    var previousMean: Double?

    @State private var selected: Int? = nil

    private struct Point: Identifiable {
        let cycle: Int
        let mean: Double?
        let low: Int
        let high: Int
        let partial: Bool
        let coverage: Double
        /// Trecho contínuo da linha (quebra onde falta leitura).
        let segment: Int
        var id: Int { cycle }
    }

    private var points: [Point] {
        var seg = 0
        var result: [Point] = []
        for i in cycles.indices {
            let c = cycles[i]
            if let m = c.mean, let lo = c.min, let hi = c.max {
                result.append(Point(cycle: i + 1, mean: m, low: lo, high: hi, partial: c.isPartial,
                                    coverage: c.coverage, segment: seg))
            } else {
                seg += 1
                result.append(Point(cycle: i + 1, mean: nil, low: 0, high: 0, partial: false, coverage: 0, segment: seg))
                seg += 1
            }
        }
        return result
    }

    private var domain: ClosedRange<Double> {
        let withData = points.filter { $0.mean != nil }
        var lo: Double = Double(withData.map { $0.low }.min() ?? 60)
        var hi: Double = Double(withData.map { $0.high }.max() ?? 100)
        if let p = previousMean { lo = min(lo, p); hi = max(hi, p) }
        let pad: Double = max(4, (hi - lo) * 0.2)
        return (lo - pad).rounded(.down)...(hi + pad).rounded(.up)
    }

    var body: some View {
        let pts = points
        let dom = domain
        let n = max(1, cycles.count)
        let xs: [Double] = (1...n).map { Double($0) }
        Chart {
            ForEach(pts) { p in
                rangeMark(p, domain: dom)
            }
            ForEach(pts.filter { $0.mean != nil }) { p in
                lineMark(p)
                pointMark(p)
            }
            if let m = sessionMean {
                sessionRule(m)
            }
            if let p = previousMean {
                previousRule(p)
            }
            if let s = selected, let p = pts.first(where: { $0.cycle == s }) {
                selectionRule(p)
            }
        }
        .chartXScale(domain: 0.4...(Double(n) + 0.6))
        .chartYScale(domain: dom)
        .chartXAxis {
            AxisMarks(values: xs) { v in
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text("C\(Int(d))").pfText(.caption).foregroundColor(PF.muted) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(PF.line)
                AxisValueLabel().foregroundStyle(PF.muted)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        select(at: location, proxy: proxy, geo: geo, count: n)
                    }
            }
        }
        .animation(PF.Motion.quick, value: selected)
    }

    private func select(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy, count: Int) {
        let origin: CGPoint = geo[proxy.plotAreaFrame].origin
        guard let x: Double = proxy.value(atX: location.x - origin.x) else { return }
        let c = Int(x.rounded())
        guard c >= 1, c <= count else { selected = nil; return }
        Haptics.play("selection")
        selected = selected == c ? nil : c
    }

    @ChartContentBuilder
    private func rangeMark(_ p: Point, domain: ClosedRange<Double>) -> some ChartContent {
        if p.mean == nil {
            BarMark(x: .value("Ciclo", Double(p.cycle)),
                    yStart: .value("Mín", domain.lowerBound),
                    yEnd: .value("Máx", domain.upperBound),
                    width: .fixed(22))
                .foregroundStyle(PF.soft)
                .annotation(position: .overlay) {
                    Text("sem dados")
                        .pfText(.caption)
                        .foregroundColor(PF.gray)
                        .fixedSize()
                        .rotationEffect(.degrees(-90))
                }
                .accessibilityLabel("Ciclo \(p.cycle)")
                .accessibilityValue("sem leitura do relógio")
        } else {
            let fill: Color = p.partial ? PF.warn : PF.pulse
            BarMark(x: .value("Ciclo", Double(p.cycle)),
                    yStart: .value("Mín", Double(p.low) - 0.5),
                    yEnd: .value("Máx", Double(p.high) + 0.5),
                    width: .fixed(22))
                .cornerRadius(6)
                .foregroundStyle(fill.opacity(p.partial ? 0.18 : 0.22))
                .accessibilityHidden(true)
        }
    }

    @ChartContentBuilder
    private func lineMark(_ p: Point) -> some ChartContent {
        LineMark(x: .value("Ciclo", Double(p.cycle)),
                 y: .value("bpm", p.mean ?? 0),
                 series: .value("Trecho", p.segment))
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .foregroundStyle(PF.pulse)
            .accessibilityHidden(true)
    }

    @ChartContentBuilder
    private func pointMark(_ p: Point) -> some ChartContent {
        let color: Color = p.partial ? PF.warn : PF.pulse
        let label: String = p.partial ? "parcial" : ""
        PointMark(x: .value("Ciclo", Double(p.cycle)), y: .value("bpm", p.mean ?? 0))
            .symbolSize(selected == p.cycle ? 150 : 70)
            .foregroundStyle(color)
            .annotation(position: .bottom, spacing: 6) {
                if p.partial {
                    Text(label).pfText(.caption, weight: .bold).foregroundColor(PF.warn)
                }
            }
            .accessibilityLabel("Ciclo \(p.cycle)")
            .accessibilityValue(accessibilityText(p))
    }

    @ChartContentBuilder
    private func sessionRule(_ m: Double) -> some ChartContent {
        RuleMark(y: .value("Média da sessão", m))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .foregroundStyle(PF.pulse.opacity(0.8))
            .annotation(position: .top, alignment: .leading, spacing: 2) {
                Text("média \(Int(m.rounded()))")
                    .pfText(.caption, weight: .bold)
                    .foregroundColor(PF.pulse)
            }
            .accessibilityLabel("Média da sessão")
            .accessibilityValue(PaloFormat.bpm(m))
    }

    @ChartContentBuilder
    private func previousRule(_ m: Double) -> some ChartContent {
        RuleMark(y: .value("Média das anteriores", m))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            .foregroundStyle(PF.muted)
            .annotation(position: .bottom, alignment: .trailing, spacing: 2) {
                Text("anteriores \(Int(m.rounded()))")
                    .pfText(.caption)
                    .foregroundColor(PF.muted)
            }
            .accessibilityLabel("Média das sessões anteriores")
            .accessibilityValue(PaloFormat.bpm(m))
    }

    @ChartContentBuilder
    private func selectionRule(_ p: Point) -> some ChartContent {
        RuleMark(x: .value("Ciclo", Double(p.cycle)))
            .lineStyle(StrokeStyle(lineWidth: 1))
            .foregroundStyle(PF.ink.opacity(0.35))
            .annotation(position: .top, alignment: .center, spacing: 0) {
                PaloChartTooltip(title: "Ciclo \(p.cycle)", lines: tooltipLines(p))
            }
            .accessibilityHidden(true)
    }

    private func tooltipLines(_ p: Point) -> [String] {
        guard let m = p.mean else { return ["sem leitura"] }
        var lines: [String] = [PaloFormat.bpm(m)]
        if p.low != p.high { lines.append("\(p.low)–\(p.high) bpm") }
        lines.append("leitura em \(Int((p.coverage * 100).rounded()))% do ciclo")
        return lines
    }

    private func accessibilityText(_ p: Point) -> String {
        guard let m = p.mean else { return "sem leitura" }
        var t = "média \(Int(m.rounded())) batimentos por minuto"
        if p.low != p.high { t += ", de \(p.low) a \(p.high)" }
        if p.partial { t += ", dados parciais" }
        return t
    }
}

/// Balão de detalhe dos gráficos.
struct PaloChartTooltip: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).pfText(.caption, weight: .bold).foregroundColor(PF.ink)
            ForEach(lines, id: \.self) { l in
                Text(l).pfText(.caption).foregroundColor(PF.muted)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(PF.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PF.line, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
        .fixedSize()
    }
}

// MARK: - Evolução entre sessões

/// Um ponto da evolução (uma sessão).
struct PaloTrendPoint: Identifiable {
    let index: Int
    let date: Date
    let value: Double
    var low: Double? = nil
    var high: Double? = nil
    var id: Int { index }
}

/// Evolução de um valor ao longo das sessões (mais antiga à esquerda).
/// Opcionalmente desenha a faixa mín–máx de cada sessão (usada na FC).
struct PaloTrendChart: View {
    let points: [PaloTrendPoint]
    let valueLabel: String
    var color: Color = PF.ink
    var format: (Double) -> String = { PaloFormat.decimal($0) }

    @State private var selected: Int? = nil

    var body: some View {
        let mean: Double = points.isEmpty ? 0 : points.map { $0.value }.reduce(0, +) / Double(points.count)
        let lows: [Double] = points.map { $0.low ?? $0.value }
        let highs: [Double] = points.map { $0.high ?? $0.value }
        let lo: Double = lows.min() ?? 0
        let hi: Double = highs.max() ?? 1
        let pad: Double = max(2, (hi - lo) * 0.2)
        let n = max(2, points.count)
        Chart {
            ForEach(points) { p in
                rangeMark(p)
                areaMark(p, floor: lo - pad)
                lineMark(p)
                pointMark(p)
            }
            meanRule(mean)
            if let s = selected, let p = points.first(where: { $0.index == s }) {
                selectionRule(p)
            }
        }
        .chartXScale(domain: 0.6...(Double(n) + 0.4))
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(PF.line)
                AxisValueLabel().foregroundStyle(PF.muted)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        let origin: CGPoint = geo[proxy.plotAreaFrame].origin
                        guard let x: Double = proxy.value(atX: location.x - origin.x) else { return }
                        let i = Int(x.rounded())
                        guard i >= 1, i <= points.count else { selected = nil; return }
                        Haptics.play("selection")
                        selected = selected == i ? nil : i
                    }
            }
        }
        .animation(PF.Motion.quick, value: selected)
    }

    @ChartContentBuilder
    private func rangeMark(_ p: PaloTrendPoint) -> some ChartContent {
        if let l = p.low, let h = p.high {
            BarMark(x: .value("Sessão", Double(p.index)),
                    yStart: .value("Mín", l), yEnd: .value("Máx", h),
                    width: .fixed(8))
                .cornerRadius(4)
                .foregroundStyle(color.opacity(0.18))
                .accessibilityHidden(true)
        }
    }

    @ChartContentBuilder
    private func areaMark(_ p: PaloTrendPoint, floor: Double) -> some ChartContent {
        AreaMark(x: .value("Sessão", Double(p.index)),
                 yStart: .value("Base", floor),
                 yEnd: .value(valueLabel, p.value))
            .interpolationMethod(.monotone)
            .foregroundStyle(LinearGradient(colors: [color.opacity(0.16), color.opacity(0)],
                                            startPoint: .top, endPoint: .bottom))
            .accessibilityHidden(true)
    }

    @ChartContentBuilder
    private func lineMark(_ p: PaloTrendPoint) -> some ChartContent {
        LineMark(x: .value("Sessão", Double(p.index)), y: .value(valueLabel, p.value))
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }

    @ChartContentBuilder
    private func pointMark(_ p: PaloTrendPoint) -> some ChartContent {
        let isLast: Bool = p.index == points.count
        PointMark(x: .value("Sessão", Double(p.index)), y: .value(valueLabel, p.value))
            .symbolSize(isLast || selected == p.index ? 90 : 36)
            .foregroundStyle(color)
            .accessibilityLabel(p.date.formatted(date: .abbreviated, time: .omitted))
            .accessibilityValue("\(valueLabel) \(format(p.value))")
    }

    @ChartContentBuilder
    private func meanRule(_ mean: Double) -> some ChartContent {
        RuleMark(y: .value("Média", mean))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .foregroundStyle(PF.muted)
            .annotation(position: .top, alignment: .trailing, spacing: 2) {
                Text("média \(format(mean))").pfText(.caption).foregroundColor(PF.muted)
            }
            .accessibilityLabel("Média")
            .accessibilityValue(format(mean))
    }

    @ChartContentBuilder
    private func selectionRule(_ p: PaloTrendPoint) -> some ChartContent {
        RuleMark(x: .value("Sessão", Double(p.index)))
            .lineStyle(StrokeStyle(lineWidth: 1))
            .foregroundStyle(PF.ink.opacity(0.35))
            .annotation(position: .top, alignment: .center, spacing: 0) {
                PaloChartTooltip(title: p.date.formatted(date: .abbreviated, time: .shortened),
                                 lines: ["\(valueLabel): \(format(p.value))"])
            }
            .accessibilityHidden(true)
    }
}

/// Mini gráfico das contagens de uma sessão (linhas do histórico).
struct PaloSparkline: View {
    let values: [Int]
    var color: Color = PF.ink

    var body: some View {
        GeometryReader { g in
            let lo = Double(values.min() ?? 0)
            let hi = Double(values.max() ?? 1)
            let span = max(1, hi - lo)
            let stepX: CGFloat = values.count > 1 ? g.size.width / CGFloat(values.count - 1) : 0
            Path { path in
                for (i, v) in values.enumerated() {
                    let x: CGFloat = CGFloat(i) * stepX
                    let y: CGFloat = g.size.height * CGFloat(1 - (Double(v) - lo) / span)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
