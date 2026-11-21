import Foundation
import ActivityKit

/// Dados da Live Activity do modo Palográfico. Compartilhado entre o app e a extensão de widget.
///
/// Regra importante: na fase Teste, `phaseInterval` é sempre `nil`, e a interface
/// da Live Activity/Dynamic Island não pode mostrar tempo, só o ciclo.
struct PaloActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// "treino", "teste" ou "livre".
        var phase: String
        /// Nome da fase para exibir ("Treino", "Teste", "Livre").
        var phaseTitle: String
        /// Ciclo atual, começando em 1.
        var currentCycle: Int
        /// Total de ciclos da fase. 0 = sem limite (Livre).
        var totalCycles: Int
        /// Intervalo da fase, usado em `Text(timerInterval:)`. Sempre nil no Teste.
        var phaseInterval: ClosedRange<Date>?
        /// Sessão encerrada (estado final exibido por alguns segundos).
        var finished: Bool

        var isTest: Bool { phase == "teste" }
        /// Livre conta para cima (tempo decorrido); Treino conta para baixo.
        var countsDown: Bool { phase == "treino" }

        var cycleShort: String {
            totalCycles > 0 ? "\(min(currentCycle, totalCycles))/\(totalCycles)" : "\(currentCycle)"
        }
    }
}
