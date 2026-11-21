import SwiftUI

// Visual da Live Activity / Dynamic Island do Palográfico.
// Fica em Shared/ para ser usado pela extensão e pela prévia dentro do app.
//
// Regra: no Teste nada aqui mostra tempo. Só a fase e o ciclo, que muda no bip
// (o app chama `activity.update` a cada sinal). Nada de `Text(timerInterval:)` no Teste.

/// Cores da Live Activity (mesma paleta escura da sessão no app).
enum PaloActivityStyle {
    static let ink = Color(red: 0xF2 / 255, green: 0xF0 / 255, blue: 0xEA / 255)
    static let muted = ink.opacity(0.6)
    static let track = ink.opacity(0.18)
    static let accent = Color(red: 0xFF / 255, green: 0x5C / 255, blue: 0x63 / 255)
    static let background = Color(red: 0x0C / 255, green: 0x0D / 255, blue: 0x10 / 255)
    static let icon = "pencil.line"
}

enum PaloText {
    static func cycleLong(_ s: PaloActivityAttributes.ContentState) -> String {
        if s.finished { return "Sessão encerrada · conte os traços" }
        if s.totalCycles > 0 { return "Ciclo \(min(s.currentCycle, s.totalCycles)) de \(s.totalCycles)" }
        return "Ciclo \(s.currentCycle)"
    }
}

/// Um traço por ciclo: feitos, atual e por vir. Muda só no sinal.
struct PaloActivityCycleBar: View {
    let state: PaloActivityAttributes.ContentState

    var body: some View {
        if state.totalCycles > 0 {
            HStack(spacing: 4) {
                ForEach(1...state.totalCycles, id: \.self) { k in
                    Capsule()
                        .fill(color(k))
                        .frame(height: 4)
                        .frame(maxWidth: k == current ? 28 : 16)
                }
            }
        }
    }

    private var current: Int { state.finished ? state.totalCycles + 1 : state.currentCycle }

    private func color(_ k: Int) -> Color {
        if k < current { return PaloActivityStyle.ink }
        if k == current { return PaloActivityStyle.accent }
        return PaloActivityStyle.track
    }
}

/// Mostra o tempo (Treino/Livre) ou só o ciclo (Teste).
struct PaloTimeOrCycle: View {
    let state: PaloActivityAttributes.ContentState
    let compact: Bool

    var body: some View {
        if state.finished {
            Image(systemName: "checkmark")
        } else if state.isTest || state.phaseInterval == nil {
            // Teste: nunca revelar tempo.
            Text(state.cycleShort)
        } else if let interval = state.phaseInterval {
            Text(timerInterval: interval, countsDown: state.countsDown)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: compact ? 52 : 96)
        }
    }
}

/// Tela bloqueada (e banner).
struct PaloLockScreenView: View {
    let state: PaloActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: state.finished ? "checkmark" : PaloActivityStyle.icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(PaloActivityStyle.background)
                    .frame(width: 36, height: 36)
                    .background(state.finished ? PaloActivityStyle.ink : PaloActivityStyle.accent, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Palográfico · \(state.phaseTitle)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PaloActivityStyle.muted)
                    Text(PaloText.cycleLong(state))
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundColor(PaloActivityStyle.ink)
                }
                Spacer(minLength: 8)
                if !state.finished {
                    PaloTimeOrCycle(state: state, compact: false)
                        .font(.system(size: 30, weight: .bold).monospacedDigit())
                        .foregroundColor(PaloActivityStyle.ink)
                }
            }
            PaloActivityCycleBar(state: state)
        }
        .padding(16)
    }
}
