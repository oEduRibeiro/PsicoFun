import SwiftUI
import UIKit

// MARK: - Raiz

/// Raiz do modo Palográfico. Troca de tela conforme o estágio da sessão.
struct PalograficoRootView: View {
    @ObservedObject var engine: PaloSessionEngine
    @ObservedObject var store: PaloStore

    var body: some View {
        Group {
            switch engine.stage {
            case .idle:
                NavigationStack { PaloPrepView(engine: engine, store: store) }
                    .transition(.opacity)
            case .countdown, .running:
                PaloSessionView(engine: engine)
                    .transition(.opacity)
            case .entry:
                NavigationStack {
                    PaloEntryView(engine: engine, store: store, cycles: engine.completedCycles)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            case .results(let record):
                NavigationStack {
                    PaloResultView(record: record, store: store, onClose: { engine.closeResults() })
                }
                .transition(.opacity)
            }
        }
        .animation(PF.Motion.spring, value: stageKey)
        .tint(PF.acc)
    }

    private var stageKey: Int {
        switch engine.stage {
        case .idle: return 0
        case .countdown, .running: return 1
        case .entry: return 2
        case .results: return 3
        }
    }
}

extension PaloMode {
    var icon: String {
        switch self {
        case .treino: return "figure.run"
        case .teste: return "checkmark.seal"
        case .livre: return "infinity"
        }
    }

    var shortMeta: String {
        switch self {
        case .treino: return "3 × 60 s"
        case .teste: return "5 × 60 s"
        case .livre: return "sem limite"
        }
    }

    /// Fatos do modo, mostrados na preparação.
    var facts: [(icon: String, text: String)] {
        switch self {
        case .treino:
            return [("repeat", "3 ciclos de 60 s"),
                    ("timer", "Cronômetro visível durante a sessão"),
                    ("chart.line.uptrend.xyaxis", "Entra no histórico de Treino")]
        case .teste:
            return [("repeat", "5 ciclos de 60 s"),
                    ("eye.slash", "Sem tempo na tela: só o número do ciclo"),
                    ("xmark.octagon", "Sem pausa: abortar descarta a sessão"),
                    ("ruler", "Total comparado às faixas de referência")]
        case .livre:
            return [("infinity", "Ciclos de 60 s até você encerrar"),
                    ("timer", "Cronômetro visível durante a sessão"),
                    ("tray", "Histórico separado: não entra na média de desempenho")]
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
    @AppStorage(PaloKeys.heartRate) private var heartRateOn = false
    @ObservedObject private var heartRate = PaloHeartRateMonitor.shared

    private var mode: PaloMode { PaloMode(rawValue: modeRaw) ?? .treino }

    var body: some View {
        PFScreen {
            hero
            PFEyebrow("Modo")
            modePicker
            modeCard
            briefingCard
            PFEyebrow("Sinais e relógio")
            signalsCard
            heartRateCard
            advancedCard
            PFEyebrow("Seus resultados")
            historyCard
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { startBar }
        .navigationTitle("Palográfico")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if heartRateOn { heartRate.activate() } }
    }

    // MARK: Cabeçalho

    private var hero: some View {
        HStack(alignment: .center, spacing: PF.Space.l) {
            VStack(alignment: .leading, spacing: PF.Space.s) {
                Text("Traços no ritmo do sinal")
                    .pfText(.largeTitle)
                    .foregroundColor(PF.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Ciclos de 60 s com sinal a cada minuto. Depois você conta os traços e vê rendimento e constância.")
                    .pfText(.callout)
                    .foregroundColor(PF.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(alignment: .bottomTrailing) {
            PaloStrokesArt()
                .frame(width: 150, height: 120)
                .opacity(0.16)
                .padding(10)
                .accessibilityHidden(true)
        }
        .background(PF.paper, in: RoundedRectangle(cornerRadius: PF.Radius.l, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PF.Radius.l, style: .continuous).stroke(PF.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: PF.Radius.l, style: .continuous))
    }

    // MARK: Modo

    private var modePicker: some View {
        HStack(spacing: PF.Space.s) {
            ForEach(PaloMode.allCases) { m in
                PaloModeTile(mode: m, selected: m == mode) {
                    guard m != mode else { return }
                    Haptics.play("selection")
                    withAnimation(PF.Motion.spring) { modeRaw = m.rawValue }
                }
            }
        }
    }

    private var modeCard: some View {
        PFCard(spacing: PF.Space.m) {
            ForEach(mode.facts.indices, id: \.self) { i in
                let f = mode.facts[i]
                HStack(alignment: .top, spacing: PF.Space.m) {
                    Image(systemName: f.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PF.ink)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    Text(f.text).pfText(.callout).foregroundColor(PF.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .id(mode)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(mode.summary)
    }

    private var briefingCard: some View {
        PFCard {
            PFCardHeader("Antes de começar", icon: "pencil.line")
            VStack(alignment: .leading, spacing: PF.Space.m) {
                step(1, "Ao começar, faça traços verticais sem parar.")
                step(2, "No sinal, faça o traço horizontal e continue.")
                step(3, "No fim, conte só os verticais de cada ciclo.")
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PF.Space.m) {
            Text("\(n)")
                .pfText(.caption, weight: .heavy)
                .foregroundColor(PF.paper)
                .frame(width: 22, height: 22)
                .background(PF.ink, in: Circle())
                .accessibilityHidden(true)
            Text(text).pfText(.callout).foregroundColor(PF.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Passo \(n): \(text)")
    }

    // MARK: Sinais

    private var signalsCard: some View {
        PFCard(spacing: PF.Space.s) {
            PFCardHeader("Sinal a cada 60 s", subtitle: "Os ajustes ficam travados durante a sessão.")
            HStack(spacing: PF.Space.m) {
                PaloSignalPreview().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pulso na tela").pfText(.body).foregroundColor(PF.ink)
                    Text("O sinal visual fica sempre ligado.").pfText(.footnote).foregroundColor(PF.muted)
                }
                Spacer()
                PFBadge("sempre", tone: .neutral)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            PFDivider()
            PFToggleRow(icon: "speaker.wave.2.fill", title: "Som",
                        subtitle: "O som de início é diferente do som do sinal.", isOn: $sound)
            PFDivider()
            PFToggleRow(icon: "iphone.radiowaves.left.and.right", title: "Vibração", isOn: $vibration)
        }
    }

    private var heartRateCard: some View {
        PFCard(spacing: PF.Space.s) {
            PFToggleRow(icon: "heart.fill", tone: .pulse, title: "Frequência cardíaca",
                        subtitle: "Opcional · lida do relógio por Bluetooth", isOn: $heartRateOn)
                .onChange(of: heartRateOn) { on in
                    if on { heartRate.activate() } else { heartRate.deactivate() }
                }
            if heartRateOn {
                PaloHRStatusRow(monitor: heartRate)
                    .transition(.opacity)
                if let name = heartRate.rememberedName {
                    Button("Esquecer \(name)") {
                        Haptics.play("light")
                        heartRate.forgetDevice()
                    }
                    .buttonStyle(PFButtonStyle(kind: .ghost, small: true))
                }
            }
            Text("Ligue a transmissão de FC no relógio (\"broadcast\"). A FC não aparece durante a sessão, só no resultado. Se o relógio não estiver conectado, a sessão segue normal e fica sem dados de FC.")
                .pfText(.footnote)
                .foregroundColor(PF.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(PF.Motion.quick, value: heartRateOn)
    }

    private var advancedCard: some View {
        PFCard(spacing: PF.Space.s) {
            PFToggleRow(icon: "bell.fill", title: "Notificação de reserva", isOn: $notificationFallback)
                .onChange(of: notificationFallback) { on in
                    guard on else { return }
                    PaloNotifier.shared.requestAuthorization { granted in
                        if !granted {
                            notificationFallback = false
                            notificationDenied = true
                        }
                    }
                }
            if notificationDenied {
                PFNote(text: "Notificações estão bloqueadas nos Ajustes do iPhone.",
                       icon: "exclamationmark.triangle.fill", tone: .warn)
            } else {
                Text("Use só se a vibração com a tela bloqueada falhar no seu aparelho: o app manda uma notificação em cada sinal.")
                    .pfText(.footnote)
                    .foregroundColor(PF.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Histórico

    private var historyCard: some View {
        let recent = store.records(for: mode)
        return PFCard(spacing: PF.Space.s) {
            if let last = recent.first {
                NavigationLink {
                    PaloResultView(record: last, store: store, onClose: nil)
                } label: {
                    lastSession(last, count: recent.count)
                }
                .buttonStyle(PFPressStyle(scale: 0.98))
                PFDivider()
            }
            NavigationLink {
                PaloHistoryView(store: store, initialMode: mode)
            } label: {
                PFRow(icon: "chart.xyaxis.line", title: "Histórico", subtitle: historySubtitle, chevron: true)
            }
            .buttonStyle(.plain)
            PFDivider()
            NavigationLink {
                PaloBandsView()
            } label: {
                PFRow(icon: "ruler", title: "Faixas de referência", subtitle: "Usadas no total do Teste", chevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var historySubtitle: String {
        let n = store.records.count
        return n == 0 ? "Nenhuma sessão ainda" : (n == 1 ? "1 sessão salva" : "\(n) sessões salvas")
    }

    private func lastSession(_ r: PaloRecord, count: Int) -> some View {
        let m = r.metrics
        return HStack(spacing: PF.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Última sessão de \(mode.title.lowercased())").pfText(.eyebrow).foregroundColor(PF.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(m.total)").pfText(.metric).foregroundColor(PF.ink)
                    Text("traços").pfText(.caption).foregroundColor(PF.muted)
                }
                Text(r.date.formatted(date: .abbreviated, time: .shortened)).pfText(.caption).foregroundColor(PF.muted)
            }
            Spacer(minLength: PF.Space.s)
            if r.counts.count > 1 {
                PaloSparkline(values: r.counts).frame(width: 84, height: 34)
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(PF.gray)
        }
        .padding(.vertical, PF.Space.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre o resultado")
    }

    // MARK: Começar

    private var startBar: some View {
        VStack(spacing: PF.Space.xs) {
            Button {
                Haptics.play("light")
                engine.start(mode: mode, config: .init(sound: sound,
                                                       vibration: vibration,
                                                       notificationFallback: notificationFallback,
                                                       heartRate: heartRateOn))
            } label: {
                Label("Começar \(mode.title.lowercased())", systemImage: "play.fill")
            }
            .buttonStyle(PFButtonStyle(kind: .accent, wide: true))
            Text("Contagem de 3 s · tela escura, sem relógio")
                .pfText(.caption)
                .foregroundColor(PF.muted)
        }
        .padding(.horizontal, PF.Space.screen)
        .padding(.top, PF.Space.m)
        .padding(.bottom, PF.Space.s)
        .frame(maxWidth: PF.Space.maxWidth)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { PFDivider() }
    }
}

/// Bloco de escolha de modo.
struct PaloModeTile: View {
    let mode: PaloMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: PF.Space.s) {
                Image(systemName: mode.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(selected ? PF.paper : PF.ink)
                Spacer(minLength: 0)
                Text(mode.title).pfText(.headline, weight: .bold).foregroundColor(selected ? PF.paper : PF.ink)
                Text(mode.shortMeta).pfText(.caption).foregroundColor(selected ? PF.paper.opacity(0.7) : PF.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .padding(PF.Space.m)
            .background(selected ? PF.ink : PF.paper, in: RoundedRectangle(cornerRadius: PF.Radius.m, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PF.Radius.m, style: .continuous)
                .stroke(selected ? PF.ink : PF.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PFPressStyle())
        .accessibilityLabel("\(mode.title), \(mode.shortMeta)")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Prévia do sinal visual (pulsa devagar; parado com "Reduzir movimento").
struct PaloSignalPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        ZStack {
            Circle().stroke(PF.acc.opacity(0.35), lineWidth: 2)
                .scaleEffect(on && !reduceMotion ? 1 : 0.45)
                .opacity(on && !reduceMotion ? 0 : 1)
            Circle().fill(PF.acc).frame(width: 10, height: 10)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { on = true }
        }
        .accessibilityHidden(true)
    }
}

/// Ilustração: traços verticais de uma folha de palográfico, com as marcas horizontais do sinal.
struct PaloStrokesArt: View {
    var body: some View {
        Canvas { ctx, size in
            let rows = 4
            let rowH: CGFloat = size.height / CGFloat(rows)
            let gap: CGFloat = 7
            var seed: UInt64 = 7
            func rnd() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((seed >> 33) % 1000) / 1000
            }
            for r in 0..<rows {
                let top: CGFloat = CGFloat(r) * rowH + rowH * 0.15
                let h: CGFloat = rowH * 0.65
                var x: CGFloat = 4
                var k = 0
                while x < size.width - 4 {
                    var p = Path()
                    let jitter: CGFloat = (rnd() - 0.5) * 3
                    p.move(to: CGPoint(x: x + jitter, y: top + rnd() * 3))
                    p.addLine(to: CGPoint(x: x - jitter, y: top + h - rnd() * 3))
                    ctx.stroke(p, with: .color(PF.ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    k += 1
                    if k % 9 == 0 {
                        var t = Path()
                        t.move(to: CGPoint(x: x + 2, y: top + h * 0.5))
                        t.addLine(to: CGPoint(x: x + gap + 2, y: top + h * 0.5))
                        ctx.stroke(t, with: .color(PF.acc), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        x += gap
                    }
                    x += gap
                }
            }
        }
    }
}

/// Status do relógio na preparação. Só informa: nunca impede de começar.
struct PaloHRStatusRow: View {
    @ObservedObject var monitor: PaloHeartRateMonitor

    var body: some View {
        HStack(spacing: PF.Space.m) {
            Image(systemName: icon)
                .foregroundColor(tone.fg)
                .frame(width: 30)
                .symbolRenderingMode(.hierarchical)
            Text(text).pfText(.callout).foregroundColor(PF.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if isConnected {
                Text(monitor.latestBPM.map { "\($0) bpm" } ?? "aguardando leitura")
                    .pfText(.metricSmall)
                    .foregroundColor(monitor.latestBPM == nil ? PF.muted : PF.pulse)
            } else if isWaiting {
                ProgressView()
            }
        }
        .padding(PF.Space.s)
        .background(PF.soft, in: RoundedRectangle(cornerRadius: PF.Radius.s, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var isConnected: Bool {
        if case .connected = monitor.status { return true }
        return false
    }

    private var isWaiting: Bool {
        switch monitor.status {
        case .searching, .connecting: return true
        default: return false
        }
    }

    private var text: String {
        switch monitor.status {
        case .off: return "Desligado"
        case .unauthorized: return "Bluetooth bloqueado nos Ajustes do iPhone"
        case .bluetoothOff: return "Bluetooth desligado"
        case .unsupported: return "Bluetooth indisponível neste aparelho"
        case .searching: return "Procurando relógio…"
        case .connecting(let name): return "Conectando a \(name)…"
        case .connected(let name): return name
        }
    }

    private var icon: String {
        switch monitor.status {
        case .connected: return "heart.fill"
        case .unauthorized, .bluetoothOff, .unsupported: return "exclamationmark.triangle.fill"
        default: return "applewatch.radiowaves.left.and.right"
        }
    }

    private var tone: PFTone {
        switch monitor.status {
        case .connected: return .pulse
        case .unauthorized, .bluetoothOff, .unsupported: return .warn
        default: return .neutral
        }
    }
}
