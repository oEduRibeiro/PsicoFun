import SwiftUI

// MARK: - Histórico

struct PaloHistoryView: View {
    @ObservedObject var store: PaloStore
    @State private var mode: PaloMode
    @State private var pendingDelete: PaloRecord?

    init(store: PaloStore, initialMode: PaloMode = .teste) {
        self.store = store
        _mode = State(initialValue: initialMode)
    }

    private var items: [PaloRecord] { store.records(for: mode) }

    private var modeOptions: [PFSegmented<PaloMode>.Option] {
        PaloMode.allCases.map { PFSegmented<PaloMode>.Option(value: $0, title: $0.title) }
    }

    var body: some View {
        List {
            row {
                PFSegmented<PaloMode>(options: modeOptions, selection: $mode)
            }

            if items.isEmpty {
                row {
                    PFCard {
                        PFEmptyState(icon: "tray", title: "Nenhuma sessão de \(mode.title.lowercased()) ainda",
                                     message: mode == .livre
                                        ? "Sessões livres ficam aqui, separadas do desempenho."
                                        : "Quando você salvar uma sessão, ela aparece aqui com o total, a média e a evolução.")
                    }
                }
            } else {
                row { summaryCard }
                if items.count >= 2 { row { trendCard } }
                if hrPoints.count >= 2 { row { hrTrendCard } }
                row { PFEyebrow("Sessões · deslize para apagar") }
                ForEach(items) { r in
                    row {
                        // Link invisível por baixo: evita a seta extra que a lista põe fora do cartão.
                        ZStack {
                            NavigationLink {
                                PaloResultView(record: r, store: store, onClose: nil)
                            } label: {
                                EmptyView()
                            }
                            .opacity(0)
                            PaloHistoryRow(record: r)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingDelete = r } label: { Label("Apagar", systemImage: "trash") }
                    }
                    .contextMenu {
                        Button(role: .destructive) { pendingDelete = r } label: { Label("Apagar sessão", systemImage: "trash") }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PF.bg.ignoresSafeArea())
        .animation(PF.Motion.spring, value: mode)
        .navigationTitle("Histórico")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Apagar esta sessão?", isPresented: Binding(get: { pendingDelete != nil },
                                                                     set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Apagar", role: .destructive) {
                if let r = pendingDelete {
                    Haptics.play("warning")
                    withAnimation { store.delete(r.id) }
                }
                pendingDelete = nil
            }
            Button("Cancelar", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Ela sai do histórico deste aparelho.")
        }
    }

    /// Linha de lista sem a aparência de lista (fundo, separador e margens do design system).
    private func row<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(maxWidth: PF.Space.maxWidth)
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets(top: 6, leading: PF.Space.screen, bottom: 6, trailing: PF.Space.screen))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    // MARK: Resumo

    private var summaryCard: some View {
        let ms = items.map { $0.metrics }
        let n = Double(ms.count)
        let avgTotal = Double(ms.map { $0.total }.reduce(0, +)) / n
        let avgMean = ms.map { $0.mean }.reduce(0, +) / n
        let avgOsc = Double(ms.map { $0.oscillation }.reduce(0, +)) / n
        let hrMeans = items.compactMap { $0.heartRate?.mean }
        var tiles: [PFStatTile] = [PFStatTile(label: "Sessões", value: "\(items.count)")]
        if mode == .teste {
            tiles.append(PFStatTile(label: "Média total", value: PaloFormat.decimal(avgTotal)))
        }
        tiles.append(PFStatTile(label: "Por ciclo", value: PaloFormat.decimal(avgMean)))
        tiles.append(PFStatTile(label: "Oscilação", value: PaloFormat.decimal(avgOsc)))
        return PFCard {
            PFCardHeader(mode == .livre ? "Livre" : "Resumo",
                         subtitle: mode == .livre ? "Separado do desempenho." : "Médias de todas as sessões de \(mode.title.lowercased()).")
            PFStatRow(items: tiles)
            if !hrMeans.isEmpty {
                PFDivider()
                HStack(spacing: PF.Space.s) {
                    Image(systemName: "heart.fill").foregroundColor(PF.pulse)
                    Text("FC média \(PaloFormat.bpm(hrMeans.reduce(0, +) / Double(hrMeans.count)))")
                        .pfText(.callout, weight: .semibold).foregroundColor(PF.ink)
                    Spacer()
                    Text("\(hrMeans.count) de \(items.count) sessões").pfText(.caption).foregroundColor(PF.muted)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Evolução

    private var trendCard: some View {
        let ordered = Array(items.reversed())
        let useTotal = mode == .teste
        let points: [PaloTrendPoint] = ordered.indices.map { i in
            let m = ordered[i].metrics
            return PaloTrendPoint(index: i + 1, date: ordered[i].date, value: useTotal ? Double(m.total) : m.mean)
        }
        let fmt: (Double) -> String = useTotal ? { "\(Int($0.rounded()))" } : { PaloFormat.decimal($0) }
        return PFCard {
            PFCardHeader("Evolução", subtitle: useTotal
                         ? "Total de cada Teste, da mais antiga à mais recente."
                         : "Média de traços por ciclo em cada sessão, da mais antiga à mais recente.")
            PaloTrendChart(points: points, valueLabel: useTotal ? "Total" : "Média por ciclo",
                           format: fmt)
                .frame(height: 190)
                .padding(.top, PF.Space.l)
            Text("Toque num ponto para ver a sessão.").pfText(.caption).foregroundColor(PF.muted)
        }
    }

    private var hrPoints: [PaloTrendPoint] {
        let ordered = items.reversed().filter { $0.heartRate?.mean != nil }
        return ordered.enumerated().map { i, r in
            let hr = r.heartRate
            return PaloTrendPoint(index: i + 1, date: r.date, value: hr?.mean ?? 0,
                                  low: hr?.min.map(Double.init), high: hr?.max.map(Double.init))
        }
    }

    private var hrTrendCard: some View {
        PFCard {
            PFCardHeader("Frequência cardíaca", subtitle: "Média (linha) e faixa mín–máx de cada sessão com FC. Só registro.",
                         icon: "heart.fill", tone: .pulse)
            PaloTrendChart(points: hrPoints, valueLabel: "FC média", color: PF.pulse,
                           format: { PaloFormat.bpm($0) })
                .frame(height: 170)
                .padding(.top, PF.Space.l)
        }
    }
}

struct PaloHistoryRow: View {
    let record: PaloRecord

    var body: some View {
        let m = record.metrics
        HStack(alignment: .center, spacing: PF.Space.m) {
            VStack(alignment: .leading, spacing: PF.Space.xs) {
                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .pfText(.caption).foregroundColor(PF.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(m.total)").pfText(.metric).foregroundColor(PF.ink)
                    Text("traços").pfText(.caption).foregroundColor(PF.muted)
                }
                Text("Média \(PaloFormat.decimal(m.mean)) · Oscilação \(m.oscillation)")
                    .pfText(.footnote).foregroundColor(PF.muted)
                HStack(spacing: 6) {
                    if let hr = record.heartRate {
                        PFBadge(hr.mean.map { PaloFormat.bpm($0) } ?? "FC sem dados", tone: hr.hasData ? .pulse : .neutral,
                                icon: hr.hasData ? "heart.fill" : "heart.slash")
                    }
                    PFBadge(record.soundOn ? "som" : "sem som", icon: record.soundOn ? "speaker.wave.2.fill" : "speaker.slash")
                    if !record.vibrationOn {
                        PFBadge("sem vibração", icon: "iphone.slash")
                    }
                }
                if !record.note.isEmpty {
                    Text(record.note).pfText(.footnote).foregroundColor(PF.ink).lineLimit(2)
                }
            }
            Spacer(minLength: PF.Space.s)
            VStack(alignment: .trailing, spacing: 6) {
                if record.counts.count > 1 {
                    PaloSparkline(values: record.counts).frame(width: 72, height: 30)
                }
                Text(record.counts.map(String.init).joined(separator: " · "))
                    .pfText(.caption).monospacedDigit().foregroundColor(PF.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(PF.gray)
        }
        .padding(PF.Space.l)
        .background(PF.paper, in: RoundedRectangle(cornerRadius: PF.Radius.m, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PF.Radius.m, style: .continuous).stroke(PF.line, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Faixas de referência

struct PaloBandsView: View {
    @AppStorage(PaloKeys.bandMedia) private var bandMedia = PaloBands.defaults.mediaMin
    @AppStorage(PaloKeys.bandAlta) private var bandAlta = PaloBands.defaults.altaMin
    @AppStorage(PaloKeys.bandSuperior) private var bandSuperior = PaloBands.defaults.superiorMin

    private var bands: PaloBands { PaloBands(mediaMin: bandMedia, altaMin: bandAlta, superiorMin: bandSuperior) }

    var body: some View {
        PFScreen {
            PFCard(spacing: PF.Space.s) {
                PFCardHeader("Limites", subtitle: "Total dos 5 ciclos do Teste.")
                field("Média a partir de", $bandMedia)
                PFDivider()
                field("Média superior ou alta a partir de", $bandAlta)
                PFDivider()
                field("Superior ou muito alta a partir de", $bandSuperior)
                if !bands.isValid {
                    PFNote(text: "Os limites precisam ser crescentes. Até corrigir, o app usa os valores padrão.",
                           icon: "exclamationmark.triangle.fill", tone: .warn)
                }
            }

            PFCard {
                PFCardHeader("Faixas em uso", subtitle: "Referência não oficial.")
                let inUse = bands.isValid ? bands : .defaults
                ForEach(inUse.all, id: \.label) { b in
                    HStack {
                        Text(b.label).pfText(.callout).foregroundColor(PF.ink)
                        Spacer()
                        Text(b.range).pfText(.footnote).monospacedDigit().foregroundColor(PF.muted)
                    }
                }
            }

            Button("Restaurar padrão (547 / 831 / 1060)") {
                Haptics.play("light")
                bandMedia = PaloBands.defaults.mediaMin
                bandAlta = PaloBands.defaults.altaMin
                bandSuperior = PaloBands.defaults.superiorMin
            }
            .buttonStyle(PFButtonStyle(kind: .ghost, wide: true))
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Faixas de referência")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ title: String, _ value: Binding<Int>) -> some View {
        HStack(spacing: PF.Space.m) {
            Text(title).pfText(.callout).foregroundColor(PF.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .pfText(.metricSmall)
                .padding(.horizontal, PF.Space.m)
                .frame(width: 100, height: 44)
                .background(PF.soft, in: RoundedRectangle(cornerRadius: PF.Radius.s, style: .continuous))
                .accessibilityLabel(title)
        }
    }
}
