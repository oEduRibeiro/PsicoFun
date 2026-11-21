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
/// atualiza o ciclo a cada bip com `activity.update`. As vistas ficam em
/// `Shared/PaloActivityViews.swift`.
struct PaloLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PaloActivityAttributes.self) { context in
            PaloLockScreenView(state: context.state)
                .activityBackgroundTint(PaloActivityStyle.background.opacity(0.88))
                .activitySystemActionForegroundColor(PaloActivityStyle.ink)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(state.phaseTitle, systemImage: PaloActivityStyle.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PaloActivityStyle.ink)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PaloTimeOrCycle(state: state, compact: false)
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundColor(PaloActivityStyle.ink)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(PaloText.cycleLong(state))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(PaloActivityStyle.muted)
                        PaloActivityCycleBar(state: state)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: PaloActivityStyle.icon)
                    .foregroundColor(PaloActivityStyle.accent)
            } compactTrailing: {
                PaloTimeOrCycle(state: state, compact: true)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundColor(PaloActivityStyle.ink)
            } minimal: {
                Image(systemName: PaloActivityStyle.icon)
                    .foregroundColor(PaloActivityStyle.accent)
            }
        }
    }
}
