import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PalograficoWidgetBundle: WidgetBundle {
    var body: some Widget {
        PaloLiveActivityWidget()
    }
}

/// Live Activity do modo Palográfico (tela bloqueada + Dynamic Island).
///
/// No Teste nada aqui mostra tempo: só a fase e "Ciclo n/5". Não usamos
/// `Text(timerInterval:)` nem `ProgressView(timerInterval:)` nesse caso; o app
/// atualiza o ciclo a cada bip com `activity.update`.
struct PaloLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PaloActivityAttributes.self) { context in
            PaloLockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(state.phaseTitle, systemImage: PaloIcon.name)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PaloTimeOrCycle(state: state, compact: false)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(PaloText.cycleLong(state))
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            } compactLeading: {
                Image(systemName: PaloIcon.name)
                    .foregroundColor(.orange)
            } compactTrailing: {
                PaloTimeOrCycle(state: state, compact: true)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundColor(.white)
            } minimal: {
                Image(systemName: PaloIcon.name)
                    .foregroundColor(.orange)
            }
        }
    }
}

enum PaloIcon {
    static let name = "pencil"
}

enum PaloText {
    static func cycleLong(_ s: PaloActivityAttributes.ContentState) -> String {
        if s.finished { return "Sessão encerrada" }
        if s.totalCycles > 0 { return "Ciclo \(min(s.currentCycle, s.totalCycles)) de \(s.totalCycles)" }
        return "Ciclo \(s.currentCycle)"
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
                .frame(maxWidth: compact ? 52 : 90)
        }
    }
}

struct PaloLockScreenView: View {
    let state: PaloActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: PaloIcon.name)
                .font(.title2)
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Palográfico · \(state.phaseTitle)")
                    .font(.headline)
                    .foregroundColor(.white)
                Text(PaloText.cycleLong(state))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            Spacer(minLength: 8)
            if !state.finished, !state.isTest, let interval = state.phaseInterval {
                Text(timerInterval: interval, countsDown: state.countsDown)
                    .font(.title.monospacedDigit().weight(.semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110)
            }
        }
        .padding(16)
    }
}
