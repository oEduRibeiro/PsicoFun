import Charts
import SwiftUI
import UIKit

// MARK: - Raiz

/// Raiz do modo Palográfico. Troca de tela conforme o estágio da sessão.
struct PalograficoRootView: View {
    @ObservedObject var engine: PaloSessionEngine
    @ObservedObject var store: PaloStore

    var body: some View {
        switch engine.stage {
        case .idle:
            NavigationStack { PaloPrepView(engine: engine, store: store) }
        case .countdown, .running:
            PaloSessionView(engine: engine)
        case .entry:
            NavigationStack {
                PaloEntryView(engine: engine, store: store, cycles: engine.completedCycles)
            }
        case .results(let record):
            NavigationStack {
                PaloResultView(record: record, store: store, onClose: { engine.closeResults() })
            }
        }
    }
}

// MARK: - Preparação

struct PaloPrepView: View {
    @ObservedObject var engine: PaloSessionEngine
    @ObservedObject var store: PaloStore

    @AppStorage(PaloKeys.mode) private var modeRaw = PaloMode.treino.rawValue
    @AppStorage(PaloKeys.sound) private var sound = true
    @AppStorage(PaloKeys.vibration) private var vibration = true
    @AppStorage(PaloKeys.notificationFallback) private var notificationFallback = false
    @State private var notificationDenied = false

    private var mode: PaloMode { PaloMode(rawValue: modeRaw) ?? .treino }

    var body: some View {
        Form {
            Section {
                Picker("Modo", selection: $modeRaw) {
                    ForEach(PaloMode.allCases) { m in
                        Text(m.title).tag(m.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text(mode.summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Section {
                Label("No sinal, faça o traço horizontal e continue. Conte só os verticais.",
                      systemImage: "info.circle")
                    .font(.callout)
            } header: {
                Text("Antes de começar")
            }

            Section {
                Toggle(isOn: $sound) { Label("Som", systemImage: "speaker.wave.2") }
                Toggle(isOn: $vibration) { Label("Vibração", systemImage: "iphone.radiowaves.left.and.right") }
            } header: {
                Text("Sinal a cada 60 s")
            } footer: {
                Text("O sinal visual (pulso na tela) fica sempre ligado. O som de início é diferente do som do sinal. Os ajustes ficam travados durante a sessão.")
            }

            Section {
                Toggle(isOn: $notificationFallback) { Label("Notificação de reserva", systemImage: "bell") }
                    .onChange(of: notificationFallback) { on in
                        guard on else { return }
                        PaloNotifier.shared.requestAuthorization { granted in
                            if !granted {
                                notificationFallback = false
                                notificationDenied = true
                            }
                        }
                    }
            } header: {
                Text("Avançado")
            } footer: {
                Text(notificationDenied
                     ? "Notificações estão bloqueadas nos Ajustes do iPhone."
                     : "Use só se a vibração com a tela bloqueada falhar no seu aparelho: o app manda uma notificação em cada sinal.")
            }

            Section {
                Button {
                    engine.start(mode: mode, config: .init(sound: sound,
                                                           vibration: vibration,
                                                           notificationFallback: notificationFallback))
                } label: {
                    Text("Começar \(mode.title.lowercased())")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                NavigationLink {
                    PaloHistoryView(store: store)
                } label: {
                    Label("Histórico", systemImage: "chart.xyaxis.line")
                }
                NavigationLink {
                    PaloBandsView()
                } label: {
                    Label("Faixas de referência", systemImage: "slider.horizontal.3")
                }
            }
        }
        .navigationTitle("Palográfico")
    }
}

// MARK: - Sessão

struct PaloSessionView: View {
    @ObservedObject var engine: PaloSessionEngine
    @State private var flash: Double = 0
    @State private var bump = false
    @State private var confirmAbort = false

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Palográfico · \(engine.mode.title)")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 24)

                Spacer()

                switch engine.stage {
                case .countdown(let n):
                    Text("\(n)")
                        .font(.system(size: 120, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                    Text("Prepare o lápis")
                        .foregroundColor(.white.opacity(0.7))
                default:
                    Text(cycleText)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .scaleEffect(bump ? 1.12 : 1)
                    if engine.mode.showsTimer {
                        timer
                            .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundColor(.white)
                    }
                }

                Spacer()

                signalsSummary
                buttons
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)

            // Pulso visual a cada sinal (não revela tempo: só acontece no bip).
            Color.white
                .opacity(flash)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onChange(of: engine.pulse) { _ in
            flash = 0.85
            bump = true
            withAnimation(.easeOut(duration: 0.5)) {
                flash = 0
                bump = false
            }
        }
        .confirmationDialog(abortTitle, isPresented: $confirmAbort, titleVisibility: .visible) {
            Button("Abortar e descartar", role: .destructive) { engine.abort() }
            Button("Continuar", role: .cancel) {}
        }
    }

    private var abortTitle: String {
        engine.mode == .livre ? "Descartar a sessão livre?" : "Abortar? A sessão será descartada."
    }

    private var cycleText: String {
        engine.totalCycles > 0
            ? "Ciclo \(engine.currentCycle) de \(engine.totalCycles)"
            : "Ciclo \(engine.currentCycle)"
    }

    @ViewBuilder private var timer: some View {
        let start = engine.startDate
        if engine.mode == .treino {
            Text(timerInterval: start...start.addingTimeInterval(TimeInterval(engine.totalCycles) * PaloConstants.cycleSeconds),
                 countsDown: true)
        } else {
            Text(timerInterval: start...start.addingTimeInterval(12 * 3600), countsDown: false)
        }
    }

    private var signalsSummary: some View {
        HStack(spacing: 16) {
            Label("Visual", systemImage: "circle.fill")
            Label(engine.config.sound ? "Som" : "Sem som",
                  systemImage: engine.config.sound ? "speaker.wave.2.fill" : "speaker.slash")
            Label(engine.config.vibration ? "Vibra" : "Sem vibrar",
                  systemImage: engine.config.vibration ? "iphone.radiowaves.left.and.right" : "iphone.slash")
        }
        .font(.caption)
        .foregroundColor(.white.opacity(0.5))
    }

    @ViewBuilder private var buttons: some View {
        if engine.mode == .livre {
            HStack(spacing: 12) {
                Button(role: .destructive) { confirmAbort = true } label: {
                    Text("Descartar").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { engine.finishLivre() } label: {
                    Text("Encerrar").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        } else {
            Button(role: .destructive) { confirmAbort = true } label: {
                Text("Abortar").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

// MARK: - Entrada das contagens

struct PaloEntryView: View {
    @ObservedObject var engine: PaloSessionEngine
    @ObservedObject var store: PaloStore
    let cycles: Int

    @State private var values: [String]
    @State private var note = ""
    @State private var confirmDiscard = false

    init(engine: PaloSessionEngine, store: PaloStore, cycles: Int) {
        self.engine = engine
        self.store = store
        self.cycles = cycles
        _values = State(initialValue: Array(repeating: "", count: cycles))
    }

    private var parsed: [Int?] {
        values.map { v in
            guard let n = Int(v.trimmingCharacters(in: .whitespaces)), PaloConstants.countRange.contains(n) else { return nil }
            return n
        }
    }

    private var isValid: Bool { cycles > 0 && parsed.allSatisfy { $0 != nil } }

    private var outliers: [Int] {
        isValid ? PaloMetrics.outliers(parsed.compactMap { $0 }) : []
    }

    var body: some View {
        Form {
            if cycles == 0 {
                Section {
                    Text("Nenhum ciclo completo para registrar.")
                    Button("Voltar") { engine.discardEntry() }
                }
            } else {
                Section {
                    ForEach(0..<cycles, id: \.self) { i in
                        HStack {
                            Text("Ciclo \(i + 1)")
                            Spacer()
                            TextField("0", text: $values[i])
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 120)
                                .foregroundColor(isInvalid(i) ? .red : .primary)
                            if outliers.contains(i) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                } header: {
                    Text("Traços verticais por ciclo")
                } footer: {
                    Text("Valores de \(PaloConstants.countRange.lowerBound) a \(PaloConstants.countRange.upperBound).")
                }

                if !outliers.isEmpty {
                    Section {
                        Label(outlierMessage, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                    }
                }

                Section {
                    TextField("Cansaço, lápis, papel…", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Nota")
                } footer: {
                    if engine.mode == .livre {
                        Text("O modo Livre fica num histórico separado e não entra na média de desempenho.")
                    }
                }

                Section {
                    Button {
                        engine.save(counts: parsed.compactMap { $0 }, note: note, into: store)
                    } label: {
                        Text("Salvar e ver resultado").font(.headline).frame(maxWidth: .infinity)
                    }
                    .disabled(!isValid)
                    Button("Descartar sessão", role: .destructive) { confirmDiscard = true }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Contagens · \(engine.mode.title)")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Descartar a sessão sem salvar?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Descartar", role: .destructive) { engine.discardEntry() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func isInvalid(_ i: Int) -> Bool {
        !values[i].isEmpty && parsed[i] == nil
    }

    private var outlierMessage: String {
        let names = outliers.map { "ciclo \($0 + 1)" }.joined(separator: ", ")
        return "O valor do \(names) destoa bastante dos outros. Confira a contagem antes de salvar."
    }
}

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
        Form {
            Section {
                HStack {
                    metric("Total", "\(metrics.total)")
                    Divider()
                    metric("Média/ciclo", PaloFormat.decimal(metrics.mean))
                    Divider()
                    metric("Oscilação", "\(metrics.oscillation)")
                }
                .padding(.vertical, 4)
            }

            Section {
                PaloCycleChart(counts: record.counts)
                    .frame(height: 200)
                    .padding(.vertical, 8)
            } header: {
                Text("Rendimento por ciclo")
            }

            if record.mode == .teste {
                Section {
                    let band = bands.classify(total: metrics.total)
                    HStack {
                        Text(band.label).font(.headline)
                        Spacer()
                        Text(band.range).foregroundColor(.secondary)
                    }
                    ForEach(bands.all, id: \.label) { b in
                        HStack {
                            Text(b.label)
                            Spacer()
                            Text(b.range).foregroundColor(.secondary)
                        }
                        .font(.footnote)
                    }
                } header: {
                    Text("Faixa do total")
                } footer: {
                    Text("Referência não oficial.")
                }
            }

            Section {
                if let last = previous.first {
                    row("Sessão anterior", "\(last.metrics.oscillation)")
                    let avg = Double(previous.map { $0.metrics.oscillation }.reduce(0, +)) / Double(previous.count)
                    row("Média das anteriores (\(previous.count))", PaloFormat.decimal(avg))
                } else {
                    Text("Primeira sessão neste modo. A oscilação será comparada com as próximas.")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Oscilação comparada")
            } footer: {
                Text("A oscilação é a soma das diferenças entre ciclos seguidos. Ela não é classificada, só comparada entre sessões.")
            }

            Section {
                row("Data", record.date.formatted(date: .abbreviated, time: .shortened))
                row("Modo", record.mode.title)
                row("Sinais", PaloFormat.signals(record))
                if !record.note.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nota").font(.caption).foregroundColor(.secondary)
                        Text(record.note)
                    }
                }
                if let dev = record.maxBeepDeviationMs {
                    row("Maior desvio dos bips", "\(Int(dev.rounded())) ms")
                }
            } header: {
                Text("Sessão")
            }

            if let onClose = onClose {
                Section {
                    Button(action: onClose) {
                        Text("Concluir").font(.headline).frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Resultado · \(record.mode.title)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.semibold).monospacedDigit())
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }
}

struct PaloCycleChart: View {
    let counts: [Int]

    private struct Point: Identifiable {
        let cycle: Int
        let value: Int
        var id: Int { cycle }
    }

    var body: some View {
        let points = counts.enumerated().map { Point(cycle: $0.offset + 1, value: $0.element) }
        Chart(points) { p in
            LineMark(x: .value("Ciclo", p.cycle), y: .value("Traços", p.value))
                .interpolationMethod(.linear)
            PointMark(x: .value("Ciclo", p.cycle), y: .value("Traços", p.value))
                .annotation(position: .top) {
                    Text("\(p.value)").font(.caption2).foregroundColor(.secondary)
                }
        }
        .chartXAxis {
            AxisMarks(values: points.map { $0.cycle }) { v in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartXScale(domain: 1...max(2, counts.count))
    }
}

enum PaloFormat {
    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    static func signals(_ r: PaloRecord) -> String {
        "visual, " + (r.soundOn ? "som" : "sem som") + ", " + (r.vibrationOn ? "vibração" : "sem vibração")
    }
}

// MARK: - Histórico

struct PaloHistoryView: View {
    @ObservedObject var store: PaloStore
    @State private var mode: PaloMode = .teste

    private var items: [PaloRecord] { store.records(for: mode) }

    var body: some View {
        List {
            Section {
                Picker("Modo", selection: $mode) {
                    ForEach(PaloMode.allCases) { m in Text(m.title).tag(m) }
                }
                .pickerStyle(.segmented)
            }

            if !items.isEmpty {
                Section {
                    summary
                } header: {
                    Text(mode == .livre ? "Livre (separado do desempenho)" : "Resumo")
                }
            }

            Section {
                if items.isEmpty {
                    Text("Nenhuma sessão de \(mode.title.lowercased()) ainda.")
                        .foregroundColor(.secondary)
                }
                ForEach(items) { r in
                    NavigationLink {
                        PaloResultView(record: r, store: store, onClose: nil)
                    } label: {
                        PaloHistoryRow(record: r)
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { items[$0].id }
                    ids.forEach(store.delete)
                }
            } header: {
                Text("Sessões")
            }
        }
        .navigationTitle("Histórico")
    }

    @ViewBuilder private var summary: some View {
        let ms = items.map { $0.metrics }
        let avgTotal = Double(ms.map { $0.total }.reduce(0, +)) / Double(ms.count)
        let avgMean = ms.map { $0.mean }.reduce(0, +) / Double(ms.count)
        let avgOsc = Double(ms.map { $0.oscillation }.reduce(0, +)) / Double(ms.count)
        HStack { Text("Sessões"); Spacer(); Text("\(items.count)").foregroundColor(.secondary) }
        if mode == .teste {
            HStack { Text("Média dos totais"); Spacer(); Text(PaloFormat.decimal(avgTotal)).foregroundColor(.secondary) }
        }
        HStack { Text("Média por ciclo"); Spacer(); Text(PaloFormat.decimal(avgMean)).foregroundColor(.secondary) }
        HStack { Text("Oscilação média"); Spacer(); Text(PaloFormat.decimal(avgOsc)).foregroundColor(.secondary) }
        if mode == .teste, items.count >= 2 {
            let ordered = items.reversed().enumerated().map {
                PaloSessionPoint(index: $0.offset + 1, total: $0.element.metrics.total)
            }
            Chart(ordered) { p in
                LineMark(x: .value("Sessão", p.index), y: .value("Total", p.total))
                PointMark(x: .value("Sessão", p.index), y: .value("Total", p.total))
            }
            .frame(height: 160)
            .padding(.vertical, 6)
        }
    }
}

struct PaloSessionPoint: Identifiable {
    let index: Int
    let total: Int
    var id: Int { index }
}

struct PaloHistoryRow: View {
    let record: PaloRecord

    var body: some View {
        let m = record.metrics
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                Spacer()
                Image(systemName: record.soundOn ? "speaker.wave.2.fill" : "speaker.slash")
                Image(systemName: record.vibrationOn ? "iphone.radiowaves.left.and.right" : "iphone.slash")
            }
            Text("Total \(m.total) · Média \(PaloFormat.decimal(m.mean)) · Oscilação \(m.oscillation)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(record.counts.map(String.init).joined(separator: " · "))
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
            if !record.note.isEmpty {
                Text(record.note).font(.caption).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Faixas de referência

struct PaloBandsView: View {
    @AppStorage(PaloKeys.bandMedia) private var bandMedia = PaloBands.defaults.mediaMin
    @AppStorage(PaloKeys.bandAlta) private var bandAlta = PaloBands.defaults.altaMin
    @AppStorage(PaloKeys.bandSuperior) private var bandSuperior = PaloBands.defaults.superiorMin

    private var bands: PaloBands { PaloBands(mediaMin: bandMedia, altaMin: bandAlta, superiorMin: bandSuperior) }

    var body: some View {
        Form {
            Section {
                field("Média a partir de", $bandMedia)
                field("Média superior ou alta a partir de", $bandAlta)
                field("Superior ou muito alta a partir de", $bandSuperior)
            } header: {
                Text("Total dos 5 ciclos do Teste")
            } footer: {
                Text(bands.isValid
                     ? "Referência não oficial."
                     : "Os limites precisam ser crescentes. Até corrigir, o app usa os valores padrão. Referência não oficial.")
            }

            Section {
                ForEach((bands.isValid ? bands : .defaults).all, id: \.label) { b in
                    HStack { Text(b.label); Spacer(); Text(b.range).foregroundColor(.secondary) }
                }
            } header: {
                Text("Faixas em uso")
            }

            Section {
                Button("Restaurar padrão (547 / 831 / 1060)") {
                    bandMedia = PaloBands.defaults.mediaMin
                    bandAlta = PaloBands.defaults.altaMin
                    bandSuperior = PaloBands.defaults.superiorMin
                }
            }
        }
        .navigationTitle("Faixas de referência")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ title: String, _ value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
        }
    }
}
