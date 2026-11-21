import SwiftUI

// MARK: - Resultado de uma sessão

struct PsicoResultView: View {
    @ObservedObject var store: PsicoStore
    @ObservedObject var nav: PsicoNav
    let sessionId: String

    @State private var open: Set<Int> = []

    var body: some View {
        Group {
            if let s = store.session(id: sessionId) {
                content(s)
            } else {
                Text("Sessão não encontrada.").foregroundColor(PF.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(PF.bg.ignoresSafeArea())
        .navigationTitle("Resultado")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ s: PsicoSession) -> some View {
        let ans = s.answers
        let ok = ans.filter(\.ok).count, tot = ans.count
        let tms = ans.reduce(0) { $0 + $1.ms }
        let weak = PsicoStats.weakKeys(ans, 4)
        let fams = PsicoStats.famStats(ans).filter { $0.n > 0 }
        var kv: [(String, String)] = [("Modo", PsicoText.mode(s.mode).name),
                                     ("Tempo médio", PsicoFormat.duration(tms / Double(max(1, tot)))),
                                     ("Tempo total", PsicoFormat.duration(tms))]
        if let e = s.est { kv.append(("Nível estimado", PsicoFormat.level(e))) }
        kv.append(("Data", PsicoFormat.date(s.created)))

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                PFCard(padding: 20) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 20) { score(ok, tot); PFKeyValues(items: kv) }
                        VStack(alignment: .leading, spacing: 16) { score(ok, tot); PFKeyValues(items: kv) }
                    }
                }

                if !weak.isEmpty {
                    PFCard {
                        Text("Onde você mais errou").font(.system(size: 19, weight: .heavy))
                        PFBars(rows: weak.map { .init(id: $0.k, label: PsicoEngine.shared.keyLabel($0.k), pct: 100 * $0.rate,
                                                      value: "\($0.err) de \($0.seen)", accent: true) })
                        Button("Treinar esses pontos agora") {
                            let avg = Double(ans.reduce(0) { $0 + $1.lvl }) / Double(max(1, tot))
                            var d = PsicoSetupDraft(mode: "foco")
                            d.lvl = max(2, Int(avg.rounded()))
                            d.n = 20
                            d.keys = Set(weak.map(\.k))
                            d.weak = weak
                            nav.draft = d
                            nav.openSetup("foco")
                        }
                        .buttonStyle(PFButtonStyle(kind: .primary))
                    }
                } else {
                    PFCard {
                        Text("Nenhum erro nesta sessão").font(.system(size: 19, weight: .heavy))
                        Text("Suba o nível ou tente a rampa até 10.").foregroundColor(PF.muted)
                    }
                }

                PFCard {
                    Text("Por tipo de questão").font(.system(size: 19, weight: .heavy))
                    PFBars(rows: fams.map { .init(id: $0.f, label: PsicoText.fams[$0.f] ?? $0.f,
                                                  pct: Double(PsicoFormat.pct($0.ok, $0.n)), value: "\($0.ok)/\($0.n)") })
                }

                PFCard {
                    HStack {
                        Text("Revisão").font(.system(size: 19, weight: .heavy))
                        Spacer()
                        Button {
                            Haptics.play("light")
                            let all = Set(0..<tot)
                            withAnimation(.easeOut(duration: 0.2)) { open = open == all ? [] : all }
                        } label: {
                            Label("Revelar todas", systemImage: "eye")
                        }
                        .buttonStyle(PFButtonStyle(kind: .ghost, small: true))
                    }
                    Text("Cada questão fica escondida até você tocar no olho.")
                        .font(.system(size: 14)).foregroundColor(PF.muted)
                    LazyVStack(spacing: 6) {
                        ForEach(0..<min(tot, s.items.count), id: \.self) { i in
                            reviewRow(s, i, ans[i])
                        }
                    }
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button("Início") {
                        nav.tab = .home
                        nav.homePath = []
                    }
                    .buttonStyle(PFButtonStyle(kind: .ghost))
                    Button("Novo treino") {
                        nav.draft = nil
                        nav.openSetup(s.mode == "foco" ? "livre" : s.mode)
                    }
                    .buttonStyle(PFButtonStyle(kind: .primary))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    private func score(_ ok: Int, _ tot: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            (Text("\(ok)").font(.system(size: 64, weight: .heavy))
                + Text("/\(tot)").font(.system(size: 29, weight: .heavy)).foregroundColor(PF.muted))
                .monospacedDigit()
            Text("\(PsicoFormat.pct(ok, tot))% de acerto").font(.system(size: 16, weight: .semibold))
        }
    }

    private func reviewRow(_ s: PsicoSession, _ i: Int, _ a: PsicoAnswer) -> some View {
        let sp = s.items[i]
        let isOpen = open.contains(i)
        return VStack(spacing: 0) {
            Button {
                Haptics.play("selection")
                withAnimation(.easeOut(duration: 0.2)) {
                    if isOpen { open.remove(i) } else { open.insert(i) }
                }
            } label: {
                HStack(spacing: 10) {
                    Text("\(i + 1). \(PsicoText.fams[sp.fam] ?? sp.fam) · nível \(sp.lvl)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PF.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isOpen {
                        Text(a.ok ? "Acertou" : "Errou")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(a.ok ? PF.ok : PF.bad)
                            .padding(.horizontal, 9).padding(.vertical, 2)
                            .background(a.ok ? PF.okBg : PF.badBg, in: Capsule())
                    }
                    PFEye(open: !isOpen).foregroundColor(PF.muted)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen, let it = PsicoEngine.shared.item(sp) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(it.prompt).font(.system(size: 17, weight: .heavy)).fixedSize(horizontal: false, vertical: true)
                    PsicoStimView(item: it, width: 280, height: 700).frame(maxWidth: .infinity)
                    PsicoOptionsGrid(item: it, selected: a.c, showColors: true, locked: true, width: 280, height: 700) { _ in }
                        .frame(maxWidth: .infinity)
                    PsicoExplanation(item: it, answer: a)
                        .padding(14)
                        .background(PF.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PF.line, lineWidth: 1))
                }
                .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 14)
                .overlay(alignment: .top) { Rectangle().fill(PF.line).frame(height: 1) }
            }
        }
        .background(PF.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PF.line, lineWidth: 1))
    }
}

// MARK: - Desempenho

struct PsicoStatsView: View {
    @ObservedObject var store: PsicoStore
    @ObservedObject var nav: PsicoNav

    var body: some View {
        let sm = store.summary
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if sm.total == 0 {
                    PFCard {
                        VStack(spacing: 14) {
                            Image(systemName: "chart.bar").font(.system(size: 34)).foregroundColor(PF.gray)
                            Text("Ainda não há respostas. Faça um treino e aqui vão aparecer seus acertos por tipo, as regras em que você mais erra e a sua evolução.")
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Escolher um modo") { nav.tab = .home }
                                .buttonStyle(PFButtonStyle(kind: .primary))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                } else {
                    content(sm)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(PF.bg.ignoresSafeArea())
        .navigationTitle("Desempenho")
    }

    private func overview(_ sm: PsicoSummary) -> [(String, String)] {
        var kv: [(String, String)] = [("Questões", "\(sm.total)"), ("Acerto geral", "\(PsicoFormat.pct(sm.ok, sm.total))%"),
                                     ("Tempo médio", PsicoFormat.duration(sm.totalMs / Double(max(1, sm.total))))]
        if let e = store.db.est.adapt { kv.append(("Nível estimado", PsicoFormat.level(e))) }
        return kv
    }

    @ViewBuilder
    private func content(_ sm: PsicoSummary) -> some View {
        PFCard { PFKeyValues(items: overview(sm), big: true) }

        if !sm.weak.isEmpty {
            PFCard {
                Text("O que você mais erra").font(.system(size: 19, weight: .heavy))
                Text("Taxa de erro em cada regra, entre as questões em que ela apareceu.")
                    .font(.system(size: 14)).foregroundColor(PF.muted)
                PFBars(rows: sm.weak.map { .init(id: $0.k, label: PsicoEngine.shared.keyLabel($0.k), pct: 100 * $0.rate,
                                                 value: "\($0.err) de \($0.seen)", accent: true) })
                Button("Treinar pontos fracos") {
                    nav.draft = nil
                    nav.openSetup("foco")
                }
                .buttonStyle(PFButtonStyle(kind: .primary))
            }
        }

        PFCard {
            Text("Acerto por tipo").font(.system(size: 19, weight: .heavy))
            PFBars(rows: sm.fams.map { f in
                let p = PsicoFormat.pct(f.ok, f.n)
                return .init(id: f.f, label: PsicoText.fams[f.f] ?? f.f, pct: Double(p), value: "\(p)% · \(f.n)")
            })
        }

        if sm.levels.count > 1 {
            PFCard {
                Text("Acerto por nível").font(.system(size: 19, weight: .heavy))
                Text("Últimas 60 questões.").font(.system(size: 14)).foregroundColor(PF.muted)
                PFBars(rows: sm.levels.map { o in
                    let p = PsicoFormat.pct(o.ok, o.n)
                    return .init(id: "\(o.level)", label: "Nível \(o.level)", pct: Double(p), value: "\(p)% · \(o.n)")
                })
            }
        }

        PFCard {
            Text("Evolução").font(.system(size: 19, weight: .heavy))
            Text("Acerto nas últimas \(sm.recent.count) sessões, da mais antiga para a mais recente.")
                .font(.system(size: 14)).foregroundColor(PF.muted)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(sm.recent, id: \.id) { r in
                    Button {
                        Haptics.play("selection")
                        nav.statsPath.append(.result(r.id))
                    } label: {
                        GeometryReader { g in
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                UnevenTopRect().fill(PF.ink)
                                    .frame(height: max(3, g.size.height * CGFloat(r.pct) / 100))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PFPressStyle())
                    .accessibilityLabel("\(r.pct)%")
                }
            }
            .frame(height: 110)
            .padding(.top, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(PF.line).frame(height: 1) }
        }

        PFCard {
            Text("Histórico").font(.system(size: 19, weight: .heavy))
            LazyVStack(spacing: 0) {
                ForEach(Array(store.db.sessions.suffix(40).reversed()), id: \.id) { s in
                    let o = s.answers.filter(\.ok).count, t = s.answers.count
                    Button {
                        Haptics.play("selection")
                        nav.statsPath.append(.result(s.id))
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(PsicoText.mode(s.mode).name).font(.system(size: 16, weight: .bold)).foregroundColor(PF.ink)
                                Text(PsicoFormat.dateTime(s.created)).font(.system(size: 13)).foregroundColor(PF.muted)
                            }
                            Spacer()
                            Text("\(o)/\(t) · \(PsicoFormat.pct(o, t))%").font(.system(size: 16, weight: .bold).monospacedDigit())
                                .foregroundColor(PF.ink)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(PF.gray)
                        }
                        .padding(.vertical, 10)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(PF.line)
                }
            }
        }
    }
}

/// Barra com cantos de cima arredondados (gráfico de evolução).
struct UnevenTopRect: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(4, rect.width / 2, rect.height)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
