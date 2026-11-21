import SwiftUI

/// Configuração do treino: tipos, nível, quantidade e tempo.
struct PsicoSetupView: View {
    @ObservedObject var store: PsicoStore
    @ObservedObject var nav: PsicoNav
    let mode: String

    @State private var d: PsicoSetupDraft
    @State private var confirmReplace = false
    @FocusState private var focused: Bool

    init(store: PsicoStore, nav: PsicoNav, mode: String) {
        self.store = store
        self.nav = nav
        self.mode = mode
        if let saved = nav.draft, saved.mode == mode {
            _d = State(initialValue: saved)
        } else {
            var x = PsicoSetupDraft(mode: mode)
            let weak = store.homeWeak
            x.lvl = Int((store.db.est.adapt ?? 3).rounded())
            x.n = mode == "rampa" ? 30 : 20
            x.keys = Set(weak.map(\.k))
            x.weak = weak
            _d = State(initialValue: x)
        }
    }

    private var m: PsicoText.Mode { PsicoText.mode(mode) }
    private var nChoices: [Int] { mode == "rampa" ? [20, 30, 50, 100] : mode == "adapt" ? [20, 30, 50] : [10, 20, 30, 50, 100] }
    private let minuteChoices = [10, 15, 20, 30, 45, 60]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(m.desc).foregroundColor(PF.muted).fixedSize(horizontal: false, vertical: true)
                PFCard {
                    VStack(alignment: .leading, spacing: 22) {
                        if mode != "foco" {
                            field("Tipos de questão") {
                                PFFlow {
                                    ForEach(PsicoText.famKeys, id: \.self) { f in
                                        PFChip(title: PsicoText.fams[f] ?? f, on: d.fams.contains(f)) {
                                            Haptics.play("selection")
                                            if d.fams.contains(f) { if d.fams.count > 1 { d.fams.remove(f) } } else { d.fams.insert(f) }
                                        }
                                    }
                                }
                            }
                        } else {
                            field("Regras para treinar") {
                                PFFlow {
                                    ForEach(d.weak) { w in
                                        PFChip(title: "\(PsicoEngine.shared.keyLabel(w.k)) · \(w.err)/\(w.seen)", on: d.keys.contains(w.k)) {
                                            Haptics.play("selection")
                                            if d.keys.contains(w.k) { if d.keys.count > 1 { d.keys.remove(w.k) } } else { d.keys.insert(w.k) }
                                        }
                                    }
                                }
                            }
                        }

                        if mode == "rampa" {
                            levelSlider("Começa no nível", $d.from)
                            levelSlider("Termina no nível", $d.to)
                        } else {
                            levelSlider(mode == "adapt" ? "Nível inicial" : mode == "foco" ? "Nível base" : "Nível", $d.lvl)
                        }

                        field("Quantidade de questões") {
                            choiceChips(nChoices, value: $d.n, custom: $d.customN, range: 1...500, unit: "questões (1 a 500)") { "\($0)" }
                        }

                        if mode == "simulado" {
                            field("Tempo total") {
                                choiceChips(minuteChoices, value: $d.minutes, custom: $d.customMinutes, range: 1...240, unit: "minutos") { "\($0) min" }
                            }
                        }

                        HStack(spacing: 8) {
                            PFEye(open: store.fbOf(mode) == "eye")
                            Text(store.fbText(mode) + (m.fbEnd ? "." : " — muda em Ajustes."))
                        }
                        .font(.system(size: 14))
                        .foregroundColor(PF.muted)

                        Button("Começar") { start() }
                            .buttonStyle(PFButtonStyle(kind: .primary, wide: true))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PF.bg.ignoresSafeArea())
        .navigationTitle(m.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { focused = false }
            }
        }
        .onChange(of: d) { nav.draft = $0 }
        .alert("Substituir sessão?", isPresented: $confirmReplace) {
            Button("Cancelar", role: .cancel) {}
            Button("Começar nova", role: .destructive) { begin() }
        } message: {
            Text("Há uma sessão em andamento. Começar outra descarta a atual.")
        }
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 16, weight: .semibold))
            content()
        }
    }

    private func levelSlider(_ title: String, _ value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text("\(value.wrappedValue)").font(.system(size: 18, weight: .bold)).foregroundColor(PF.acc)
                    .monospacedDigit()
            }
            Slider(value: Binding(get: { Double(value.wrappedValue) },
                                  set: { new in
                                      let v = Int(new.rounded())
                                      if v != value.wrappedValue { Haptics.play("selection"); value.wrappedValue = v }
                                  }),
                   in: 1...10, step: 1)
                .tint(PF.acc)
        }
    }

    private func choiceChips(_ values: [Int], value: Binding<Int>, custom: Binding<Bool>, range: ClosedRange<Int>,
                             unit: String, label: @escaping (Int) -> String) -> some View {
        let isCustom = custom.wrappedValue || !values.contains(value.wrappedValue)
        return VStack(alignment: .leading, spacing: 10) {
            PFFlow {
                ForEach(values, id: \.self) { v in
                    PFChip(title: label(v), on: v == value.wrappedValue && !isCustom) {
                        Haptics.play("selection")
                        value.wrappedValue = v
                        custom.wrappedValue = false
                        focused = false
                    }
                }
                PFChip(title: "Outro", on: isCustom) {
                    Haptics.play("selection")
                    custom.wrappedValue = true
                    focused = true
                }
            }
            if isCustom {
                HStack(spacing: 8) {
                    TextField("", value: Binding(get: { value.wrappedValue },
                                                 set: { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) }),
                              format: .number)
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .font(.system(size: 16, weight: .bold))
                        .padding(.horizontal, 10)
                        .frame(width: 96, height: 42)
                        .background(PF.paper, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(PF.ink, lineWidth: 1.5))
                    Text(unit).font(.system(size: 14)).foregroundColor(PF.muted)
                }
            }
        }
    }

    private func start() {
        focused = false
        if store.current != nil { confirmReplace = true } else { begin() }
    }

    private func begin() {
        let c = PsicoConfig(mode: mode, fams: PsicoText.famKeys.filter { d.fams.contains($0) }, lvl: d.lvl, from: d.from, to: d.to,
                            n: d.n, minutes: d.minutes, keys: d.weak.map(\.k).filter { d.keys.contains($0) })
        store.newSession(c)
        Haptics.play("light")
        nav.quizShown = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { nav.homePath = [] }
    }
}
