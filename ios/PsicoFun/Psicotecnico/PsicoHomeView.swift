import SwiftUI

/// Figuras de exemplo da tela inicial (fixas, geradas uma vez em segundo plano).
final class PsicoSamples: ObservableObject {
    static let shared = PsicoSamples()
    @Published private(set) var hero: [PFFig] = []
    @Published private(set) var modes: [String: PFFig] = [:]
    private var loading = false

    func load() {
        guard hero.isEmpty, !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let e = PsicoEngine.shared
            let h = e.item(PsicoItemSpec(fam: "mat", lvl: 4, seed: 20261119))?.stim.figs ?? []
            var m: [String: PFFig] = [:]
            for mode in PsicoText.modes {
                let (f, l, s) = mode.sample
                if let it = e.item(PsicoItemSpec(fam: f, lvl: l, seed: s)) { m[mode.key] = it.options[it.answer].fig }
            }
            DispatchQueue.main.async {
                self.hero = h
                self.modes = m
                self.loading = false
            }
        }
    }
}

struct PsicoHomeView: View {
    @ObservedObject var store: PsicoStore
    @ObservedObject var nav: PsicoNav
    @ObservedObject private var samples = PsicoSamples.shared
    @State private var confirmDiscard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                if let cur = store.current { continueCard(cur) }
                Text("Escolha um modo")
                    .font(.system(size: 19, weight: .heavy))
                    .padding(.top, 14)
                VStack(spacing: 10) {
                    ForEach(PsicoText.modes, id: \.key) { m in modeCard(m) }
                }
                if let w = store.homeWeak.first {
                    (Text("Seu ponto mais fraco agora: ") + Text(PsicoEngine.shared.keyLabel(w.k)).bold()
                        + Text(" (\(w.err) erros em \(w.seen))."))
                        .font(.system(size: 15))
                        .foregroundColor(PF.muted)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(PF.bg.ignoresSafeArea())
        .navigationTitle("Treinar")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { samples.load() }
        .alert("Descartar sessão?", isPresented: $confirmDiscard) {
            Button("Cancelar", role: .cancel) {}
            Button("Descartar", role: .destructive) { store.discardCurrent() }
        } message: {
            Text("As respostas desta sessão não entram no histórico.")
        }
    }

    private var hero: some View {
        let s = store.summary
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 24) {
                heroText(s)
                heroGrid.frame(width: 240)
            }
            .frame(minWidth: 560)
            VStack(alignment: .leading, spacing: 16) {
                heroText(s)
                heroGrid.frame(maxWidth: 220).frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(PF.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(PF.line, lineWidth: 1))
    }

    private func heroText(_ s: PsicoSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Psicotécnico visual")
                .font(.system(size: 32, weight: .heavy))
                .lineSpacing(-4)
            Text("Sequências, matrizes, analogias, rotação e figura intrusa. Cada questão é gerada na hora a partir de regras e verificada por um solucionador: só existe uma resposta certa.")
                .foregroundColor(PF.muted)
                .fixedSize(horizontal: false, vertical: true)
            if s.total > 0 {
                Text("\(s.total) questões respondidas · \(PsicoFormat.pct(s.ok, s.total))% de acerto"
                     + (store.db.est.adapt.map { " · nível estimado " + PsicoFormat.level($0) } ?? ""))
                    .font(.system(size: 15, weight: .semibold))
            }
            Label("Salvo neste aparelho", systemImage: "iphone")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PF.muted)
        }
    }

    private var heroGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(0..<9, id: \.self) { i in
                if i < 8 {
                    PsicoCell(fig: samples.hero.count > i ? samples.hero[i] : nil)
                } else {
                    PsicoQuestionCell()
                }
            }
        }
    }

    private func continueCard(_ cur: PsicoSession) -> some View {
        let done = cur.answers.count
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                continueText(cur, done)
                Spacer(minLength: 8)
                continueButtons
            }
            VStack(alignment: .leading, spacing: 12) {
                continueText(cur, done)
                continueButtons
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(PF.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func continueText(_ cur: PsicoSession, _ done: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sessão em andamento").font(.system(size: 16, weight: .bold)).foregroundColor(PF.paper)
            Text("\(PsicoText.mode(cur.mode).name) · \(done) de \(cur.n) respondidas")
                .font(.system(size: 14)).foregroundColor(PF.paper.opacity(0.75))
        }
    }

    private var continueButtons: some View {
        HStack(spacing: 8) {
            Button("Descartar") { confirmDiscard = true }
                .buttonStyle(InvertedGhostStyle())
            Button("Continuar") {
                Haptics.play("light")
                nav.quizShown = true
            }
            .buttonStyle(PFButtonStyle(kind: .accent))
        }
    }

    private func modeCard(_ m: PsicoText.Mode) -> some View {
        let disabled = m.key == "foco" && store.homeWeak.isEmpty
        let fb = store.fbOf(m.key)
        return Button {
            if disabled {
                store.showToast("Faça alguns treinos primeiro: o modo usa os seus erros.")
                Haptics.play("warning")
                return
            }
            Haptics.play("light")
            nav.homePath.append(.setup(m.key))
        } label: {
            HStack(spacing: 14) {
                Group {
                    if let f = samples.modes[m.key] { PsicoFigure(fig: f) } else { Color.clear.aspectRatio(1, contentMode: .fit) }
                }
                .padding(4)
                .frame(width: 64)
                .background(PF.cell, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(PF.line, lineWidth: 1.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).font(.system(size: 17, weight: .bold)).foregroundColor(PF.ink)
                    Text(m.desc).font(.system(size: 14)).foregroundColor(PF.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        PFEye(open: fb == "eye")
                        Text(store.fbText(m.key))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(fb == "end" || fb == "off" ? PF.acc : PF.muted)
                    .padding(.top, 4)
                    if disabled {
                        Text("Disponível depois de errar algumas questões")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(PF.muted)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundColor(PF.gray)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(PF.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PF.line, lineWidth: 1))
            .opacity(disabled ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PFPressStyle())
    }
}

private struct InvertedGhostStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(PF.paper)
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PF.paper.opacity(0.35), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Célula de figura (matriz, sequência, analogia).
struct PsicoCell: View {
    let fig: PFFig?
    var label: String? = nil
    var padding: CGFloat = 4
    var radius: CGFloat = 8

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(PF.cell)
            if let f = fig { PsicoFigure(fig: f).padding(padding) }
            if let l = label {
                Text(l).font(.system(size: 12, weight: .bold)).foregroundColor(PF.muted)
                    .padding(.top, 3).padding(.leading, 6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(PF.line, lineWidth: 1.5))
    }
}

/// Célula do "?" (tracejada em vermelho).
struct PsicoQuestionCell: View {
    var radius: CGFloat = 8
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(PF.acc, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(PF.cell))
            .aspectRatio(1, contentMode: .fit)
            .overlay(Text("?").font(.system(size: 26, weight: .heavy)).foregroundColor(PF.acc).minimumScaleFactor(0.5))
    }
}
