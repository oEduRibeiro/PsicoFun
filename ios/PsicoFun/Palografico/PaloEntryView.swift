import SwiftUI

// MARK: - Entrada das contagens

struct PaloEntryView: View {
    @ObservedObject var engine: PaloSessionEngine
    @ObservedObject var store: PaloStore
    let cycles: Int

    @State private var values: [String]
    @State private var note = ""
    @State private var confirmDiscard = false
    @FocusState private var focused: Int?

    /// Foco no campo de nota.
    private static let noteField = -1

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
        Group {
            if cycles == 0 {
                PFScreen {
                    PFCard {
                        PFEmptyState(icon: "hourglass", title: "Nenhum ciclo completo",
                                     message: "A sessão terminou antes do primeiro sinal. Não há contagem para registrar.",
                                     actionTitle: "Voltar", action: { engine.discardEntry() })
                    }
                }
            } else {
                form
            }
        }
        .navigationTitle("Contagens · \(engine.mode.title)")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Descartar a sessão sem salvar?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Descartar", role: .destructive) { engine.discardEntry() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var form: some View {
        PFScreen {
            PFCard {
                PFCardHeader("Quantos traços verticais?",
                             subtitle: "Conte cada ciclo na folha e digite aqui. Valores de \(PaloConstants.countRange.lowerBound) a \(PaloConstants.countRange.upperBound).",
                             icon: "pencil.line")
                VStack(spacing: PF.Space.s) {
                    ForEach(0..<cycles, id: \.self) { i in
                        cycleRow(i)
                    }
                }
            }

            liveSummary

            if !outliers.isEmpty {
                PFNote(text: outlierMessage, icon: "exclamationmark.triangle.fill", tone: .warn)
                    .transition(.opacity)
            }

            PFCard(spacing: PF.Space.s) {
                Text("Nota").pfText(.eyebrow).foregroundColor(PF.muted)
                TextField("Cansaço, lápis, papel…", text: $note, axis: .vertical)
                    .lineLimit(2...5)
                    .pfText(.body)
                    .focused($focused, equals: Self.noteField)
                    .padding(PF.Space.m)
                    .background(PF.soft, in: RoundedRectangle(cornerRadius: PF.Radius.s, style: .continuous))
                if engine.mode == .livre {
                    Text("O modo Livre fica num histórico separado e não entra na média de desempenho.")
                        .pfText(.footnote).foregroundColor(PF.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .animation(PF.Motion.quick, value: outliers)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if let f = focused, f >= 0 {
                    Button("Anterior") { focused = max(0, f - 1) }.disabled(f == 0)
                    Spacer()
                    Button(f < cycles - 1 ? "Próximo" : "OK") {
                        focused = f < cycles - 1 ? f + 1 : nil
                    }
                    .fontWeight(.semibold)
                } else {
                    Spacer()
                    Button("OK") { focused = nil }.fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { focused = 0 }
        }
    }

    private func cycleRow(_ i: Int) -> some View {
        let invalid = isInvalid(i)
        let outlier = outliers.contains(i)
        let border: Color = invalid ? PF.bad : (focused == i ? PF.ink : (outlier ? PF.warn : Color.clear))
        return HStack(spacing: PF.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ciclo \(i + 1)").pfText(.headline).foregroundColor(PF.ink)
                if invalid {
                    Text("Use um número de 0 a 400").pfText(.caption).foregroundColor(PF.bad)
                } else if outlier {
                    Text("Destoa dos outros: confira").pfText(.caption).foregroundColor(PF.warn)
                }
            }
            Spacer(minLength: PF.Space.s)
            TextField("0", text: $values[i])
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .pfText(.metric)
                .foregroundColor(invalid ? PF.bad : PF.ink)
                .focused($focused, equals: i)
                .padding(.horizontal, PF.Space.m)
                .frame(width: 120, height: 52)
                .background(PF.soft, in: RoundedRectangle(cornerRadius: PF.Radius.s, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PF.Radius.s, style: .continuous).stroke(border, lineWidth: 1.5))
                .accessibilityLabel("Traços no ciclo \(i + 1)")
        }
        .animation(PF.Motion.quick, value: invalid)
    }

    /// Total, média e oscilação calculados enquanto digita.
    private var liveSummary: some View {
        let filled = parsed.compactMap { $0 }
        let m = PaloMetrics(counts: filled)
        let ready = !filled.isEmpty
        return PFCard(padding: 16) {
            PFStatRow(items: [
                PFStatTile(label: "Total", value: ready ? "\(m.total)" : "—"),
                PFStatTile(label: "Média", value: ready ? PaloFormat.decimal(m.mean) : "—"),
                PFStatTile(label: "Oscilação", value: filled.count > 1 ? "\(m.oscillation)" : "—"),
            ])
            if !isValid {
                Text("\(filled.count) de \(cycles) ciclos preenchidos")
                    .pfText(.caption).foregroundColor(PF.muted)
            }
        }
    }

    private var saveBar: some View {
        VStack(spacing: PF.Space.xs) {
            Button {
                Haptics.play("success")
                focused = nil
                engine.save(counts: parsed.compactMap { $0 }, note: note, into: store)
            } label: {
                Text("Salvar e ver resultado")
            }
            .buttonStyle(PFButtonStyle(kind: .accent, wide: true))
            .disabled(!isValid)
            Button("Descartar sessão") { confirmDiscard = true }
                .pfText(.footnote, weight: .semibold)
                .foregroundColor(PF.bad)
                .frame(minHeight: 36)
        }
        .padding(.horizontal, PF.Space.screen)
        .padding(.top, PF.Space.m)
        .padding(.bottom, PF.Space.xs)
        .frame(maxWidth: PF.Space.maxWidth)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { PFDivider() }
    }

    private func isInvalid(_ i: Int) -> Bool {
        !values[i].isEmpty && parsed[i] == nil
    }

    private var outlierMessage: String {
        let names = outliers.map { "ciclo \($0 + 1)" }.joined(separator: ", ")
        return "O valor do \(names) destoa bastante dos outros. Confira a contagem antes de salvar."
    }
}
