import SwiftUI

// MARK: - Resultado

struct PaloResultView: View {
    let record: PaloRecord
    @ObservedObject var store: PaloStore
    var onClose: (() -> Void)?

    @AppStorage(PaloKeys.bandMedia) private var bandMedia = PaloBands.defaults.mediaMin
    @AppStorage(PaloKeys.bandAlta) private var bandAlta = PaloBands.defaults.altaMin
    @AppStorage(PaloKeys.bandSuperior) private var bandSuperior = PaloBands.defaults.superiorMin

    private var metrics: PaloMetrics { record.metrics }

    private var bands: PaloBands {
        let b = PaloBands(mediaMin: bandMedia, altaMin: bandAlta, superiorMin: bandSuperior)
        return b.isValid ? b : .defaults
    }

    /// Sessões anteriores do mesmo modo, da mais recente para a mais antiga.
    private var previous: [PaloRecord] {
        store.records(for: record.mode).filter { $0.id != record.id && $0.date < record.date }
    }

    var body: some View {
        PFScreen {
            hero
            cyclesCard
            if record.mode == .teste { bandsCard }
            if let hr = record.heartRate {
                PaloHRCard(heartRate: hr, previous: previous)
            }
            oscillationCard
            detailsCard
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let onClose = onClose {
                Button {
                    Haptics.play("light")
                    onClose()
                } label: { Text("Concluir") }
                    .buttonStyle(PFButtonStyle(kind: .primary, wide: true))
                    .padding(.horizontal, PF.Space.screen)
                    .padding(.vertical, PF.Space.m)
                    .frame(maxWidth: PF.Space.maxWidth)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
                    .overlay(alignment: .top) { PFDivider() }
            }
        }
        .navigationTitle("Resultado · \(record.mode.title)")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Cabeçalho

    private var hero: some View {
        PFCard(padding: 20, spacing: PF.Space.l) {
            HStack(spacing: PF.Space.s) {
                PFBadge(record.mode.title, tone: .ink, icon: record.mode.icon)
                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .pfText(.caption).foregroundColor(PF.muted)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: PF.Space.xxs) {
                Text("Total de traços").pfText(.eyebrow).foregroundColor(PF.muted)
                HStack(alignment: .firstTextBaseline, spacing: PF.Space.s) {
                    Text("\(metrics.total)").pfText(.display).foregroundColor(PF.ink)
                    if record.mode == .teste {
                        PFBadge(bands.classify(total: metrics.total).label, tone: .neutral)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            PFStatRow(items: [
                PFStatTile(label: "Média/ciclo", value: PaloFormat.decimal(metrics.mean)),
                PFStatTile(label: "Oscilação", value: "\(metrics.oscillation)"),
                PFStatTile(label: "Ciclos", value: "\(record.counts.count)"),
            ])
        }
    }

    // MARK: Ciclos

    private var cyclesCard: some View {
        PFCard {
            PFCardHeader("Rendimento por ciclo",
                         subtitle: "Traços verticais em cada minuto. A linha tracejada é a média da sessão.")
            PaloCycleChart(counts: record.counts)
                .frame(height: 220)
                .padding(.top, PF.Space.s)
            if !PaloMetrics.outliers(record.counts).isEmpty {
                HStack(spacing: 6) {
                    Circle().fill(PF.warn).frame(width: 8, height: 8)
                    Text("Ciclo que destoa bastante dos outros").pfText(.caption).foregroundColor(PF.muted)
                }
            }
        }
    }

    // MARK: Faixas (Teste)

    private var bandsCard: some View {
        PFCard {
            PFCardHeader("Faixa do total", subtitle: "Referência não oficial.")
            PaloBandScale(bands: bands, total: metrics.total)
                .padding(.vertical, PF.Space.xs)
            VStack(spacing: 0) {
                let current = bands.classify(total: metrics.total)
                ForEach(bands.all, id: \.label) { b in
                    let on = b == current
                    HStack {
                        Text(b.label).pfText(.callout, weight: on ? .bold : .regular).foregroundColor(PF.ink)
                        Spacer()
                        Text(b.range).pfText(.footnote).monospacedDigit().foregroundColor(PF.muted)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, PF.Space.s)
                    .background(on ? PF.soft : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    // MARK: Oscilação

    private var oscillationCard: some View {
        PFCard {
            PFCardHeader("Oscilação comparada",
                         subtitle: "Soma das diferenças entre ciclos seguidos. Não é classificada, só comparada entre sessões do mesmo modo.")
            if let last = previous.first {
                let avg = Double(previous.map { $0.metrics.oscillation }.reduce(0, +)) / Double(previous.count)
                PFStatRow(items: [
                    PFStatTile(label: "Esta sessão", value: "\(metrics.oscillation)"),
                    PFStatTile(label: "Anterior", value: "\(last.metrics.oscillation)"),
                    PFStatTile(label: "Média (\(previous.count))", value: PaloFormat.decimal(avg)),
                ])
            } else {
                PFNote(text: "Primeira sessão neste modo. A oscilação será comparada com as próximas.", icon: "sparkles")
            }
        }
    }

    // MARK: Detalhes

    private var detailsCard: some View {
        PFCard(spacing: PF.Space.s) {
            PFCardHeader("Sessão")
            PFRow(icon: "calendar", title: "Data", value: record.date.formatted(date: .abbreviated, time: .shortened))
            PFDivider()
            PFRow(icon: record.mode.icon, title: "Modo", value: record.mode.title)
            PFDivider()
            PFRow(icon: "bell", title: "Sinais", value: PaloFormat.signals(record))
            if let dev = record.maxBeepDeviationMs {
                PFDivider()
                PFRow(icon: "metronome", title: "Maior desvio dos bips", value: "\(Int(dev.rounded())) ms")
            }
            if !record.note.isEmpty {
                PFDivider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nota").pfText(.eyebrow).foregroundColor(PF.muted)
                    Text(record.note).pfText(.body).foregroundColor(PF.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, PF.Space.xs)
            }
        }
    }
}

enum PaloFormat {
    static func bpm(_ value: Double) -> String {
        "\(Int(value.rounded())) bpm"
    }

    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    static func signals(_ r: PaloRecord) -> String {
        "visual, " + (r.soundOn ? "som" : "sem som") + ", " + (r.vibrationOn ? "vibração" : "sem vibração")
    }
}

// MARK: - Régua das faixas

/// Régua com as quatro faixas do total e um marcador no total da sessão.
struct PaloBandScale: View {
    let bands: PaloBands
    let total: Int

    var body: some View {
        let lo: Double = 0
        let hi: Double = Double(bands.superiorMin) * 1.25
        let stops: [Double] = [lo, Double(bands.mediaMin), Double(bands.altaMin), Double(bands.superiorMin), hi]
        let shades: [Double] = [0.10, 0.28, 0.5, 0.8]
        let clamped: Double = min(max(Double(total), lo), hi)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                let w: CGFloat = g.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { i in
                            let frac: CGFloat = CGFloat((stops[i + 1] - stops[i]) / (hi - lo))
                            Rectangle().fill(PF.ink.opacity(shades[i]))
                                .frame(width: max(0, w * frac - 2))
                        }
                    }
                    .frame(height: 12)
                    .clipShape(Capsule())
                    .frame(maxHeight: .infinity)

                    let x: CGFloat = w * CGFloat((clamped - lo) / (hi - lo))
                    VStack(spacing: 2) {
                        Text("\(total)").pfText(.caption, weight: .heavy).foregroundColor(PF.acc).fixedSize()
                        RoundedRectangle(cornerRadius: 2).fill(PF.acc).frame(width: 4, height: 22)
                    }
                    .offset(x: min(max(0, x - 12), w - 24))
                    .frame(width: 24)
                    .offset(y: -6)
                }
            }
            .frame(height: 44)
            HStack {
                Text("\(bands.mediaMin)")
                Spacer()
                Text("\(bands.altaMin)")
                Spacer()
                Text("\(bands.superiorMin)")
            }
            .pfText(.caption)
            .foregroundColor(PF.muted)
            .padding(.horizontal, PF.Space.xl)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Faixa do total")
        .accessibilityValue("\(total): \(bands.classify(total: total).label)")
    }
}

// MARK: - Frequência cardíaca (resultado)

/// FC da sessão. Só registro: sem classificação e sem "alto/baixo é melhor".
struct PaloHRCard: View {
    let heartRate: PaloHeartRate
    /// Sessões anteriores do mesmo modo (a comparação usa só as que têm FC).
    let previous: [PaloRecord]

    private var previousMean: Double? {
        let means = previous.compactMap { $0.heartRate?.mean }
        guard !means.isEmpty else { return nil }
        return means.reduce(0, +) / Double(means.count)
    }

    private var previousCount: Int { previous.compactMap { $0.heartRate?.mean }.count }

    var body: some View {
        PFCard {
            PFCardHeader("Frequência cardíaca", subtitle: "Só registro, sem classificação.", icon: "heart.fill", tone: .pulse)
            if heartRate.hasData {
                PFStatRow(items: [
                    PFStatTile(label: "Média", value: heartRate.mean.map { "\(Int($0.rounded()))" } ?? "—", unit: "bpm", tone: .pulse),
                    PFStatTile(label: "Mínima", value: heartRate.min.map(String.init) ?? "—", unit: "bpm"),
                    PFStatTile(label: "Máxima", value: heartRate.max.map(String.init) ?? "—", unit: "bpm"),
                ])
                coverageRow
                PaloHRChart(cycles: heartRate.cycles, sessionMean: heartRate.mean, previousMean: previousMean)
                    .frame(height: 230)
                    .padding(.top, PF.Space.l)
                legend
                Text("Toque num ciclo do gráfico para ver os números.")
                    .pfText(.caption).foregroundColor(PF.muted)
                cycleTable
                if let p = previousMean, let m = heartRate.mean {
                    PFNote(text: comparisonText(mean: m, previous: p), icon: "arrow.left.arrow.right")
                }
            } else {
                PFEmptyState(icon: "heart.slash", title: "Sem leituras do relógio",
                             message: "O recurso estava ligado, mas nenhuma leitura chegou durante a sessão. Antes de começar, ative a transmissão de FC (\"broadcast\") no relógio e confira o status na preparação.")
            }
            Text(footer).pfText(.caption).foregroundColor(PF.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var coverageRow: some View {
        let pct = Int((heartRate.coverage * 100).rounded())
        return HStack(spacing: PF.Space.s) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(PF.soft)
                    Capsule().fill(heartRate.isPartial ? PF.warn : PF.pulse)
                        .frame(width: max(4, g.size.width * CGFloat(heartRate.coverage)))
                }
            }
            .frame(height: 6)
            Text("leitura em \(pct)% do tempo").pfText(.caption).foregroundColor(PF.muted).fixedSize()
            if heartRate.isPartial {
                PFBadge("parcial", tone: .warn)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cobertura das leituras")
        .accessibilityValue("\(pct)% do tempo" + (heartRate.isPartial ? ", com ciclos parciais" : ""))
    }

    private var legend: some View {
        PFFlow(spacing: PF.Space.m) {
            legendItem(AnyView(Circle().fill(PF.pulse).frame(width: 8, height: 8)), "média do ciclo")
            legendItem(AnyView(RoundedRectangle(cornerRadius: 3).fill(PF.pulse.opacity(0.25)).frame(width: 10, height: 14)), "mín–máx")
            legendItem(AnyView(dash(PF.pulse)), "média da sessão")
            if previousMean != nil {
                legendItem(AnyView(dash(PF.muted)), "anteriores")
            }
            if heartRate.isPartial {
                legendItem(AnyView(Circle().fill(PF.warn).frame(width: 8, height: 8)), "parcial")
            }
        }
        .accessibilityHidden(true)
    }

    private func dash(_ c: Color) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in Capsule().fill(c).frame(width: 4, height: 2) }
        }
    }

    private func legendItem(_ mark: AnyView, _ text: String) -> some View {
        HStack(spacing: 5) {
            mark
            Text(text).pfText(.caption).foregroundColor(PF.muted)
        }
    }

    private var cycleTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ciclo").frame(maxWidth: .infinity, alignment: .leading)
                Text("Média").frame(width: 72, alignment: .trailing)
                Text("Mín–máx").frame(width: 84, alignment: .trailing)
            }
            .pfText(.eyebrow)
            .foregroundColor(PF.muted)
            .padding(.vertical, 6)
            .accessibilityHidden(true)
            ForEach(heartRate.cycles.indices, id: \.self) { i in
                PFDivider()
                cycleLine(i, heartRate.cycles[i])
            }
        }
        .padding(.top, PF.Space.s)
    }

    private func cycleLine(_ i: Int, _ c: PaloHRCycle) -> some View {
        HStack {
            HStack(spacing: 6) {
                Text("Ciclo \(i + 1)").pfText(.callout).foregroundColor(PF.ink)
                if c.isPartial { PFBadge("parcial", tone: .warn) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let mean = c.mean {
                Text("\(Int(mean.rounded()))").pfText(.metricSmall).foregroundColor(PF.ink)
                    .frame(width: 72, alignment: .trailing)
                Text(rangeText(c)).pfText(.footnote).monospacedDigit().foregroundColor(PF.muted)
                    .frame(width: 84, alignment: .trailing)
            } else {
                Text("sem dados").pfText(.footnote).foregroundColor(PF.gray)
                    .frame(width: 156, alignment: .trailing)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ciclo \(i + 1)")
        .accessibilityValue(accessibilityValue(c))
    }

    private func rangeText(_ c: PaloHRCycle) -> String {
        guard let lo = c.min, let hi = c.max else { return "—" }
        return lo == hi ? "\(lo)" : "\(lo)–\(hi)"
    }

    private func accessibilityValue(_ c: PaloHRCycle) -> String {
        guard let mean = c.mean else { return "sem dados" }
        var t = "média \(Int(mean.rounded())) bpm"
        if let lo = c.min, let hi = c.max, lo != hi { t += ", de \(lo) a \(hi)" }
        if c.isPartial { t += ", parcial" }
        return t
    }

    private func comparisonText(mean: Double, previous p: Double) -> String {
        let diff = Int((mean - p).rounded())
        let sign = diff > 0 ? "+" : ""
        return "Média das \(previousCount) sessões anteriores com FC: \(PaloFormat.bpm(p)). Esta sessão: \(sign)\(diff) bpm."
    }

    private var footer: String {
        var parts: [String] = []
        if let name = heartRate.deviceName, heartRate.hasData { parts.append("Fonte: \(name).") }
        if heartRate.isPartial {
            parts.append("Ciclos parciais tiveram leitura em menos de \(Int(PaloHRCycle.partialThreshold * 100))% do tempo.")
        }
        parts.append("A FC muda com café, sono, postura e outros fatores, e não indica desempenho.")
        return parts.joined(separator: " ")
    }
}
