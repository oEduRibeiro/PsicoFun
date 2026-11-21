import SwiftUI
import UIKit

/// Tela da questão. Treino: escolhe, confirma e (conforme o ajuste) vê a correção.
/// Simulado: navega livremente, cronômetro total e gabarito só no fim.
struct PsicoQuizView: View {
    @ObservedObject var store: PsicoStore
    @ObservedObject var nav: PsicoNav

    @State private var pending = -1
    @State private var revealed = false
    @State private var sheetOpen = false
    @State private var showPalette = false
    @State private var qStart = Date()
    @State private var confirmQuit = false
    @State private var confirmFinish = false

    var body: some View {
        Group {
            if let s = store.current, s.idx < s.n, let it = store.item(s, s.idx) {
                content(s, it)
            } else {
                PF.bg.overlay(ProgressView())
            }
        }
        .background(PF.bg.ignoresSafeArea())
        .onAppear {
            store.ensureCurrentItem()
            resetQuestion()
            if let s = store.current, s.idx >= s.n { finish(early: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if isSim { addTime(); store.save() }
        }
    }

    private var isSim: Bool { store.current?.mode == "simulado" }

    // MARK: Layout

    private func content(_ s: PsicoSession, _ it: PsicoItem) -> some View {
        let i = s.idx
        let a = s.answer(at: i)
        let sim = s.mode == "simulado"
        let locked = !sim && a != nil
        let showFb = locked && (s.fb == "auto" || (s.fb == "eye" && revealed))
        let showCol = showFb || (locked && s.fb == "eye" && store.settings.showCorrect)
        let sel = a?.c ?? pending

        return GeometryReader { geo in
            let w = min(geo.size.width - 32, 760)
            let h = geo.size.height
            VStack(spacing: 0) {
                header(s, it, a, sim: sim, locked: locked)
                ScrollView {
                    VStack(spacing: 0) {
                        Text(it.prompt)
                            .font(.system(size: w < 568 ? 17 : 22, weight: .heavy))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2).padding(.bottom, 12)
                        PsicoStimView(item: it, width: w, height: h)
                            .padding(.bottom, it.stim.type == "none" ? 0 : 14)
                        PsicoOptionsGrid(item: it, selected: sel, showColors: showCol, locked: locked,
                                         width: w, height: h) { pick($0) }
                        if sim && showPalette { palette(s).padding(.top, 16) }
                    }
                    .frame(width: w)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar(s, it, a, sim: sim, locked: locked, showFb: showFb)
            }
        }
        .task(id: deadlineToken(s, locked: locked)) { await waitDeadline(locked: locked) }
        .onChange(of: s.idx) { _ in
            store.ensureCurrentItem()
            resetQuestion()
        }
        .sheet(isPresented: Binding(get: { showFb && sheetOpen }, set: { sheetOpen = $0 })) {
            PsicoExplanationSheet(item: it, answer: a, isLast: i >= s.n - 1,
                                  onClose: { sheetOpen = false },
                                  onNext: { sheetOpen = false; advance() })
        }
        .alert("Encerrar agora?", isPresented: $confirmQuit) {
            Button("Continuar", role: .cancel) {}
            Button("Encerrar", role: .destructive) {
                if sim { addTime() }
                finish(early: true)
            }
        } message: {
            Text(sim ? "O simulado será corrigido com o que você respondeu até aqui."
                     : "As questões respondidas entram no resultado; as restantes ficam de fora.")
        }
        .alert("Finalizar o simulado?", isPresented: $confirmFinish) {
            Button("Voltar", role: .cancel) {}
            Button("Finalizar") { addTime(); finish(early: true) }
        } message: {
            let blank = blankCount(s)
            Text("\(blank) " + (blank == 1 ? "questão está sem resposta e contará" : "questões estão sem resposta e contarão") + " como erro.")
        }
    }

    private func header(_ s: PsicoSession, _ it: PsicoItem, _ a: PsicoAnswer?, sim: Bool, locked: Bool) -> some View {
        let done = sim ? s.ans.filter { ($0?.c ?? -1) >= 0 }.count : s.idx
        let st = store.settings
        return VStack(spacing: 8) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(PF.line)
                    Capsule().fill(PF.acc).frame(width: g.size.width * CGFloat(done) / CGFloat(max(1, s.n)))
                        .animation(.easeOut(duration: 0.3), value: done)
                }
            }
            .frame(height: 4)
            HStack(spacing: 8) {
                (Text("\(s.idx + 1)").font(.system(size: 18, weight: .heavy))
                    + Text("/\(s.n)").font(.system(size: 14, weight: .medium)).foregroundColor(PF.muted))
                    .monospacedDigit()
                Spacer(minLength: 4)
                Text((PsicoText.short[it.fam] ?? it.fam) + (st.showLevel ? " · nível \(it.lvl)" : ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PF.muted)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(PF.paper, in: Capsule())
                    .overlay(Capsule().stroke(PF.line, lineWidth: 1))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if st.timer || sim || st.qTime > 0 {
                    clockView(s, a, sim: sim, locked: locked)
                }
                Button {
                    confirmQuit = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PF.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Encerrar sessão")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(PF.bg)
    }

    private func clockView(_ s: PsicoSession, _ a: PsicoAnswer?, sim: Bool, locked: Bool) -> some View {
        let lim = Double(store.settings.qTime) * 1000
        return Group {
            if locked, let a = a {
                Text(PsicoFormat.clock(a.ms)).foregroundColor(PF.ink)
            } else {
                TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                    let el = ctx.date.timeIntervalSince(qStart) * 1000
                    if sim {
                        let left = (s.limit ?? 0) - (s.elapsed + el)
                        Text(PsicoFormat.clock(left)).foregroundColor(left < 60000 ? PF.acc : PF.ink)
                    } else if lim > 0 {
                        let left = lim - el
                        Text(PsicoFormat.clock(left)).foregroundColor(left < 10000 ? PF.acc : PF.ink)
                    } else {
                        Text(PsicoFormat.clock(el)).foregroundColor(PF.ink)
                    }
                }
            }
        }
        .font(.system(size: 16, weight: .bold).monospacedDigit())
        .frame(minWidth: 46, alignment: .trailing)
    }

    @ViewBuilder
    private func bottomBar(_ s: PsicoSession, _ it: PsicoItem, _ a: PsicoAnswer?, sim: Bool, locked: Bool, showFb: Bool) -> some View {
        let last = s.idx >= s.n - 1
        HStack(spacing: 10) {
            if sim {
                Button { move(-1) } label: { Image(systemName: "arrow.left") }
                    .buttonStyle(PFButtonStyle(kind: .ghost))
                    .disabled(s.idx == 0)
                    .accessibilityLabel("Questão anterior")
                Button {
                    Haptics.play("light")
                    withAnimation(.easeOut(duration: 0.2)) { showPalette.toggle() }
                } label: { Text("Questões") }
                    .buttonStyle(PFButtonStyle(kind: .ghost))
                Spacer(minLength: 0)
                if !last {
                    Button { move(1) } label: { Text("Próxima →") }
                        .buttonStyle(PFButtonStyle(kind: .primary))
                } else {
                    Button { askFinish(s) } label: { Text("Finalizar") }
                        .buttonStyle(PFButtonStyle(kind: .primary))
                }
            } else if !locked {
                Text(pending < 0 ? "Escolha uma alternativa" : "Marcou \(it.letters[pending]). Pode trocar.")
                    .font(.system(size: 14))
                    .foregroundColor(PF.muted)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button("Confirmar") { if pending >= 0 { lock(pending, timeout: false) } }
                    .buttonStyle(PFButtonStyle(kind: .primary))
                    .frame(minWidth: 130)
                    .disabled(pending < 0)
            } else {
                if s.fb == "off" {
                    Text("Resposta registrada.").font(.system(size: 14)).foregroundColor(PF.muted)
                } else {
                    Button {
                        Haptics.play("light")
                        revealed = true
                        sheetOpen = true
                    } label: {
                        Label(showFb ? "Abrir explicação" : "Ver explicação", systemImage: "eye")
                    }
                    .buttonStyle(PFButtonStyle(kind: .ghost))
                }
                Spacer(minLength: 0)
                Button(last ? "Ver resultado" : "Avançar →") { advance() }
                    .buttonStyle(PFButtonStyle(kind: .primary))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(PF.bg.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(PF.line).frame(height: 0.5) }
    }

    private func palette(_ s: PsicoSession) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
            ForEach(0..<s.n, id: \.self) { j in
                let done = (s.answer(at: j)?.c ?? -1) >= 0
                let cur = j == s.idx
                Button {
                    Haptics.play("selection")
                    addTime()
                    store.mutateCurrent { $0.idx = j }
                } label: {
                    Text("\(j + 1)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(cur ? PF.acc : PF.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(done ? PF.soft : PF.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(cur ? PF.acc : done ? PF.muted : PF.line, lineWidth: 1.5))
                }
                .buttonStyle(PFPressStyle())
            }
        }
    }

    // MARK: Ações

    private func resetQuestion() {
        pending = -1
        revealed = false
        sheetOpen = false
        qStart = Date()
        if let s = store.current {
            let next = s.idx + 1
            if next < s.items.count { PsicoEngine.shared.prefetch([s.items[next]]) }
        }
    }

    private func pick(_ i: Int) {
        guard let s = store.current else { return }
        if s.mode == "simulado" {
            let ms = s.answer(at: s.idx)?.ms ?? 0
            store.mutateCurrent { cur in
                cur.setAnswer(store.record(cur, cur.idx, c: i, ms: ms), at: cur.idx)
            }
            Haptics.play("selection")
            return
        }
        guard s.answer(at: s.idx) == nil else { return }
        if pending != i { Haptics.play("selection") }
        pending = i
    }

    private func lock(_ c: Int, timeout: Bool) {
        guard let s = store.current else { return }
        let ms = Date().timeIntervalSince(qStart) * 1000
        guard let a = store.lockAnswer(c, ms: ms, timeout: timeout) else { return }
        pending = -1
        revealed = false
        sheetOpen = s.fb == "auto"
        let colored = s.fb == "auto" || (s.fb == "eye" && store.settings.showCorrect)
        Haptics.play(colored ? (a.ok ? "success" : "error") : "light")
    }

    private func advance() {
        guard let s = store.current else { return }
        Haptics.play("light")
        if s.idx + 1 >= s.n {
            store.mutateCurrent { $0.idx += 1 }
            finish(early: false)
        } else {
            store.mutateCurrent { $0.idx += 1 }
        }
    }

    private func move(_ d: Int) {
        guard let s = store.current else { return }
        Haptics.play("light")
        addTime()
        let j = max(0, min(s.n - 1, s.idx + d))
        store.mutateCurrent { $0.idx = j }
    }

    /// Simulado: soma o tempo gasto na questão atual.
    private func addTime() {
        guard store.current?.mode == "simulado" else { return }
        let el = Date().timeIntervalSince(qStart) * 1000
        store.mutateCurrent({ cur in
            cur.elapsed += el
            if var a = cur.answer(at: cur.idx) {
                a.ms += el
                cur.setAnswer(a, at: cur.idx)
            } else {
                cur.setAnswer(store.record(cur, cur.idx, c: -1, ms: el), at: cur.idx)
            }
        }, persist: false)
        qStart = Date()
    }

    private func blankCount(_ s: PsicoSession) -> Int {
        s.n - s.ans.filter { ($0?.c ?? -1) >= 0 }.count
    }

    private func askFinish(_ s: PsicoSession) {
        if blankCount(s) > 0 {
            confirmFinish = true
        } else {
            addTime()
            finish(early: true)
        }
    }

    private func finish(early: Bool, message: String? = nil) {
        let id = store.finish(early: early)
        sheetOpen = false
        nav.quizShown = false
        if let m = message { store.showToast(m) }
        if let id = id {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { nav.openResult(id) }
        } else {
            nav.tab = .home
        }
    }

    // MARK: Tempo limite

    private func deadlineToken(_ s: PsicoSession, locked: Bool) -> String {
        "\(s.id)-\(s.idx)-\(locked)-\(qStart.timeIntervalSince1970)-\(store.settings.qTime)"
    }

    private func waitDeadline(locked: Bool) async {
        guard let s = store.current else { return }
        let sim = s.mode == "simulado"
        let lim = Double(store.settings.qTime) * 1000
        let el = Date().timeIntervalSince(qStart) * 1000
        let left: Double
        if sim {
            left = (s.limit ?? 0) - (s.elapsed + el)
        } else if lim > 0 && !locked {
            left = lim - el
        } else {
            return
        }
        if left > 0 {
            try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000))
            if Task.isCancelled { return }
        }
        guard let cur = store.current, cur.id == s.id, cur.idx == s.idx else { return }
        if sim {
            addTime()
            finish(early: true, message: "Tempo do simulado esgotado.")
        } else if cur.answer(at: cur.idx) == nil {
            lock(pending >= 0 ? pending : -1, timeout: pending < 0)
        }
    }
}

/// Folha nativa com a explicação (arrastar para baixo fecha).
struct PsicoExplanationSheet: View {
    let item: PsicoItem
    let answer: PsicoAnswer?
    let isLast: Bool
    let onClose: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(PF.soft, in: Circle())
                }
                .foregroundColor(PF.ink)
                .accessibilityLabel("Fechar explicação")
                Text("Explicação").font(.system(size: 17, weight: .bold))
                Spacer()
                Button(isLast ? "Ver resultado" : "Avançar →", action: onNext)
                    .buttonStyle(PFButtonStyle(kind: .primary, small: true))
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 10)
            Divider().overlay(PF.line)
            ScrollView {
                PsicoExplanation(item: item, answer: answer)
                    .padding(16)
            }
        }
        .background(PF.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
