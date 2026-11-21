import SwiftUI

// MARK: - Estímulo (sequência, matriz, analogia, modelo)

struct PsicoStimView: View {
    let item: PsicoItem
    /// Largura e altura disponíveis, para caber sem rolar no celular.
    let width: CGFloat
    let height: CGFloat

    private var phone: Bool { width < 600 }

    var body: some View {
        let figs = item.stim.figs
        switch item.stim.type {
        case "seq":
            HStack(spacing: phone ? 4 : 8) {
                ForEach(figs.indices, id: \.self) { i in
                    PsicoCell(fig: figs[i], padding: phone ? 2 : 4, radius: phone ? 6 : 8)
                }
                PsicoQuestionCell(radius: phone ? 6 : 8)
            }
            .frame(maxWidth: 760)
        case "mat":
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: phone ? 6 : 8), count: 3), spacing: phone ? 6 : 8) {
                ForEach(figs.indices, id: \.self) { i in PsicoCell(fig: figs[i]) }
                PsicoQuestionCell()
            }
            .frame(width: min(width, 330, max(180, height * 0.38)))
        case "ana":
            HStack(spacing: phone ? 4 : 8) {
                PsicoCell(fig: figs[0], label: "A")
                op(":")
                PsicoCell(fig: figs[1], label: "B")
                op("::")
                PsicoCell(fig: figs[2], label: "C")
                op(":")
                PsicoQuestionCell()
            }
            .frame(maxWidth: 520)
        case "model":
            PsicoCell(fig: figs.first, label: "Modelo", padding: 16)
                .frame(width: min(170, max(110, height * 0.26)))
        default:
            EmptyView()
        }
    }

    private func op(_ s: String) -> some View {
        Text(s).font(.system(size: 16, weight: .heavy)).foregroundColor(PF.muted).fixedSize()
    }
}

// MARK: - Alternativas

enum PsicoOptState: Equatable { case none, sel, ok, bad }

struct PsicoOptionButton: View {
    let letter: String
    let fig: PFFig
    let state: PsicoOptState
    let locked: Bool
    let compact: Bool
    let action: () -> Void

    var body: some View {
        let border: Color = state == .sel ? PF.ink : state == .ok ? PF.ok : state == .bad ? PF.bad : PF.line
        let bg: Color = state == .ok ? PF.okBg : state == .bad ? PF.badBg : PF.cell
        let letterColor: Color = state == .sel ? PF.ink : state == .ok ? PF.ok : state == .bad ? PF.bad : PF.muted
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous).fill(bg)
                PsicoFigure(fig: fig)
                    .padding(.top, compact ? 17 : 22)
                    .padding([.horizontal, .bottom], compact ? 4 : 6)
                Text(letter)
                    .font(.system(size: compact ? 12 : 13, weight: .bold))
                    .foregroundColor(letterColor)
                    .padding(.top, compact ? 2 : 4).padding(.leading, compact ? 6 : 8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                    .strokeBorder(border, lineWidth: state == .none ? 2 : 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PFPressStyle(scale: locked ? 1 : 0.96))
        .accessibilityLabel("Alternativa \(letter)")
        .accessibilityAddTraits(state == .sel ? .isSelected : [])
        .animation(.easeOut(duration: 0.15), value: state)
    }
}

struct PsicoOptionsGrid: View {
    let item: PsicoItem
    let selected: Int
    let showColors: Bool
    let locked: Bool
    let width: CGFloat
    let height: CGFloat
    let onPick: (Int) -> Void

    private var phone: Bool { width < 600 }

    private func state(_ i: Int) -> PsicoOptState {
        if showColors {
            if i == item.answer { return .ok }
            if i == selected { return .bad }
        }
        return i == selected ? .sel : .none
    }

    private func button(_ i: Int) -> some View {
        PsicoOptionButton(letter: item.letters[i], fig: item.options[i].fig, state: state(i), locked: locked, compact: phone) {
            onPick(i)
        }
    }

    var body: some View {
        let n = item.options.count
        if n == 8 {
            let gap: CGFloat = phone ? 8 : 10
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: 4), spacing: gap) {
                ForEach(0..<n, id: \.self) { i in button(i) }
            }
            .frame(width: min(width, phone ? 360 : 520, max(220, height * 0.52)))
        } else if phone {
            // 3 + 2, como na prova impressa.
            let w = min(width, 340, max(220, height * 0.46))
            let gap: CGFloat = 8
            let cell = (w - 2 * gap) / 3
            VStack(spacing: gap) {
                HStack(spacing: gap) { ForEach(0..<min(3, n), id: \.self) { i in button(i).frame(width: cell) } }
                HStack(spacing: gap) { ForEach(3..<n, id: \.self) { i in button(i).frame(width: cell) } }
            }
            .frame(width: w)
        } else {
            HStack(spacing: 10) { ForEach(0..<n, id: \.self) { i in button(i) } }
                .frame(maxWidth: 760)
        }
    }
}

// MARK: - Explicação

/// Mini figura usada no resumo e nas cadeias da explicação.
struct PsicoMini: View {
    enum Kind { case plain, ans, bad }
    let fig: PFFig
    var kind: Kind = .plain
    var caption: String? = nil
    var width: CGFloat = 58

    var body: some View {
        VStack(spacing: 3) {
            PsicoFigure(fig: fig)
                .padding(2)
                .background(PF.cell, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(kind == .ans ? PF.ok : kind == .bad ? PF.bad : PF.line, lineWidth: kind == .plain ? 1.5 : 3))
                .frame(width: width, height: width)
            if let c = caption {
                Text(c).font(.system(size: 11)).foregroundColor(PF.muted).lineLimit(1).fixedSize()
            }
        }
    }
}

/// Cadeia de valores/figuras de um passo ("Linha 1: 2 › 3 › 4").
struct PsicoChainView: View {
    let chain: [PFChainEl]

    private var rows: [[PFChainEl]] {
        var out: [[PFChainEl]] = [[]]
        for el in chain {
            if el.gap != nil { out.append([]) } else { out[out.count - 1].append(el) }
        }
        return out.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                PFFlow(spacing: 6) {
                    ForEach(rows[r].indices, id: \.self) { i in element(rows[r][i]) }
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func element(_ x: PFChainEl) -> some View {
        if let lab = x.lab {
            Text(lab).font(.system(size: 12, weight: .bold)).foregroundColor(PF.muted)
                .frame(minWidth: 58, minHeight: 28, alignment: .leading)
        } else if let o = x.o {
            Text(o).font(.system(size: 16, weight: .heavy)).foregroundColor(PF.muted).frame(minHeight: 28)
        } else if let f = x.fig {
            PsicoMini(fig: f, kind: x.ans == true ? .ans : .plain, caption: x.cap)
        } else if let v = x.v {
            let ans = x.ans == true
            Text(v)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(ans ? PF.ok : PF.ink)
                .lineLimit(1)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .frame(minWidth: 32)
                .background(PF.cell, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(ans ? PF.ok : PF.line, lineWidth: ans ? 2.5 : 1.5))
        }
    }
}

/// Conteúdo da explicação (folha durante o treino ou bloco na revisão).
struct PsicoExplanation: View {
    let item: PsicoItem
    let answer: PsicoAnswer?

    var body: some View {
        let L = item.letters
        let c = answer?.c ?? -1
        VStack(alignment: .leading, spacing: 0) {
            verdict(L, c)
            recap(c).padding(.top, 10)

            Text("Como resolver").font(.system(size: 13, weight: .heavy)).foregroundColor(PF.muted)
                .padding(.top, 16).padding(.bottom, 4)
            ForEach(item.steps.indices, id: \.self) { i in
                let st = item.steps[i]
                VStack(alignment: .leading, spacing: 0) {
                    if i > 0 { Divider().overlay(PF.line) }
                    (Text(st.h + ".").bold() + Text(" " + st.t))
                        .font(.system(size: 15))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    if let ch = st.ch, !ch.isEmpty { PsicoChainView(chain: ch) }
                }
                .padding(.bottom, 8)
            }

            if let a = answer, !a.ok, c >= 0, c < item.options.count {
                let o = item.options[c]
                let d = o.diag ?? PFDiag(lines: [o.why ?? ""], traps: [], vis: nil)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Onde \(L[c]) erra").font(.system(size: 13, weight: .heavy)).foregroundColor(PF.bad)
                    ForEach(d.lines.indices, id: \.self) { i in
                        Text(d.lines[i]).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
                    }
                    if let vis = d.vis, !vis.isEmpty { PsicoChainView(chain: vis) }
                    ForEach((d.traps ?? []).indices, id: \.self) { i in
                        Text(d.traps![i]).font(.system(size: 15, weight: .semibold)).padding(.top, 4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PF.badBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Para qualquer questão deste tipo").font(.system(size: 13, weight: .bold)).foregroundColor(PF.muted)
                Text(item.method).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PF.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 12)
        }
    }

    private func verdict(_ L: [String], _ c: Int) -> some View {
        let head: String
        if let a = answer {
            head = a.to == true ? "Tempo esgotado." : c < 0 ? "Sem resposta." : a.ok ? "Você acertou." : "Você marcou \(L[c])."
        } else {
            head = ""
        }
        return (Text(head + " Correta: ") + Text(L[item.answer]).foregroundColor(PF.ok))
            .font(.system(size: 16, weight: .bold))
    }

    private func recap(_ c: Int) -> some View {
        let F = item.stim.figs
        let A = item.options[item.answer].fig
        let L = item.letters
        return PFFlow(spacing: 16) {
            switch item.stim.type {
            case "mat":
                VStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { r in
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { col in
                                let i = r * 3 + col
                                if i < F.count {
                                    PsicoMini(fig: F[i], width: 48)
                                } else {
                                    PsicoMini(fig: A, kind: .ans, width: 48)
                                }
                            }
                        }
                    }
                }
            case "seq":
                HStack(spacing: 4) {
                    ForEach(F.indices, id: \.self) { i in PsicoMini(fig: F[i], width: 40) }
                    PsicoMini(fig: A, kind: .ans, width: 40)
                }
            case "ana":
                HStack(spacing: 4) {
                    PsicoMini(fig: F[0], caption: "A", width: 46)
                    PsicoMini(fig: F[1], caption: "B", width: 46)
                    PsicoMini(fig: F[2], caption: "C", width: 46)
                    PsicoMini(fig: A, kind: .ans, caption: "D", width: 46)
                }
            case "model":
                PsicoMini(fig: F[0], caption: "modelo", width: 64)
            default:
                EmptyView()
            }
            HStack(alignment: .top, spacing: 10) {
                PsicoMini(fig: A, kind: .ans, caption: "certa: \(L[item.answer])")
                if c >= 0 && c != item.answer && c < item.options.count {
                    PsicoMini(fig: item.options[c].fig, kind: .bad, caption: "sua: \(L[c])")
                }
            }
        }
    }
}
