import SwiftUI
import UIKit

// MARK: - Sessão

/// Tela da sessão: escura, sem barra de status e sem nada que mude com o tempo no Teste.
/// O único movimento acontece no sinal (pulso, onda e o número do ciclo).
struct PaloSessionView: View {
    @ObservedObject var engine: PaloSessionEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var flash: Double = 0
    @State private var bump = false
    @State private var ripple: CGFloat = 0
    @State private var rippleOpacity: Double = 0
    @State private var confirmAbort = false

    var body: some View {
        ZStack {
            PF.stage.ignoresSafeArea()

            // Onda que sai do centro a cada sinal.
            Circle()
                .stroke(PF.acc, lineWidth: 3)
                .frame(width: 220, height: 220)
                .scaleEffect(0.6 + ripple * 1.6)
                .opacity(rippleOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: PF.Space.l)
                center
                Spacer(minLength: PF.Space.l)
                buttons
            }
            .padding(.horizontal, PF.Space.xl)
            .padding(.top, PF.Space.l)
            .padding(.bottom, PF.Space.xl)
            .frame(maxWidth: 560)

            // Pulso visual a cada sinal (não revela tempo: só acontece no bip).
            PF.stageInk
                .opacity(flash)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onChange(of: engine.pulse) { _ in signal() }
        .confirmationDialog(abortTitle, isPresented: $confirmAbort, titleVisibility: .visible) {
            Button(engine.mode == .livre ? "Descartar" : "Abortar e descartar", role: .destructive) { engine.abort() }
            Button("Continuar", role: .cancel) {}
        }
    }

    // MARK: Partes

    private var topBar: some View {
        HStack(spacing: PF.Space.s) {
            HStack(spacing: 6) {
                Image(systemName: engine.mode.icon).imageScale(.small)
                Text("Palográfico · \(engine.mode.title)")
            }
            .pfText(.footnote, weight: .semibold)
            .foregroundColor(PF.stageInk)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(PF.stageLine, in: Capsule())
            Spacer()
            HStack(spacing: 10) {
                signalIcon("circle.fill", on: true, label: "Sinal visual")
                signalIcon(engine.config.sound ? "speaker.wave.2.fill" : "speaker.slash.fill", on: engine.config.sound,
                           label: engine.config.sound ? "Som ligado" : "Sem som")
                signalIcon(engine.config.vibration ? "iphone.radiowaves.left.and.right" : "iphone.slash", on: engine.config.vibration,
                           label: engine.config.vibration ? "Vibração ligada" : "Sem vibração")
            }
            .font(.system(size: 13, weight: .semibold))
        }
    }

    private func signalIcon(_ name: String, on: Bool, label: String) -> some View {
        Image(systemName: name)
            .foregroundColor(on ? PF.stageInk.opacity(0.75) : PF.stageMuted.opacity(0.6))
            .accessibilityLabel(label)
    }

    @ViewBuilder private var center: some View {
        switch engine.stage {
        case .countdown(let n):
            VStack(spacing: PF.Space.m) {
                Text("Prepare o lápis").pfText(.eyebrow).foregroundColor(PF.stageMuted)
                Text("\(n)")
                    .font(.system(size: 150, weight: .heavy).monospacedDigit())
                    .foregroundColor(PF.stageInk)
                    .contentTransition(.numericText())
                    .animation(PF.Motion.bouncy, value: n)
                    .accessibilityLabel("Começa em \(n)")
            }
        default:
            VStack(spacing: PF.Space.l) {
                Text("Ciclo").pfText(.eyebrow).foregroundColor(PF.stageMuted)
                    .accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(engine.currentCycle)")
                        .font(.system(size: 140, weight: .heavy).monospacedDigit())
                        .foregroundColor(PF.stageInk)
                        .contentTransition(.numericText())
                    if engine.totalCycles > 0 {
                        Text("/\(engine.totalCycles)")
                            .font(.system(size: 44, weight: .heavy).monospacedDigit())
                            .foregroundColor(PF.stageMuted)
                    }
                }
                .scaleEffect(bump && !reduceMotion ? 1.08 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(cycleText)

                if engine.totalCycles > 0 {
                    cycleDots
                }

                if engine.mode.showsTimer {
                    timer
                        .font(.system(size: 40, weight: .semibold).monospacedDigit())
                        .foregroundColor(PF.stageInk.opacity(0.8))
                        .padding(.top, PF.Space.s)
                }
            }
        }
    }

    /// Um traço por ciclo: feitos, atual e por vir. Muda só no sinal (nunca com o tempo).
    private var cycleDots: some View {
        HStack(spacing: 8) {
            ForEach(1...engine.totalCycles, id: \.self) { k in
                Capsule()
                    .fill(k < engine.currentCycle ? PF.stageInk : (k == engine.currentCycle ? PF.acc : PF.stageLine))
                    .frame(width: k == engine.currentCycle ? 30 : 14, height: 6)
            }
        }
        .animation(reduceMotion ? nil : PF.Motion.spring, value: engine.currentCycle)
        .accessibilityHidden(true)
    }

    private var cycleText: String {
        engine.totalCycles > 0
            ? "Ciclo \(engine.currentCycle) de \(engine.totalCycles)"
            : "Ciclo \(engine.currentCycle)"
    }

    @ViewBuilder private var timer: some View {
        let start = engine.startDate
        if engine.mode == .treino {
            Text(timerInterval: start...start.addingTimeInterval(TimeInterval(engine.totalCycles) * PaloConstants.cycleSeconds),
                 countsDown: true)
        } else {
            Text(timerInterval: start...start.addingTimeInterval(12 * 3600), countsDown: false)
        }
    }

    @ViewBuilder private var buttons: some View {
        if engine.mode == .livre {
            HStack(spacing: PF.Space.m) {
                Button { confirmAbort = true } label: { Text("Descartar").frame(maxWidth: .infinity) }
                    .buttonStyle(PaloStageButtonStyle(prominent: false))
                Button {
                    Haptics.play("light")
                    engine.finishLivre()
                } label: { Text("Encerrar").frame(maxWidth: .infinity) }
                    .buttonStyle(PaloStageButtonStyle(prominent: true))
            }
        } else {
            Button { confirmAbort = true } label: {
                Label("Abortar", systemImage: "xmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(PaloStageButtonStyle(prominent: false))
        }
    }

    private var abortTitle: String {
        engine.mode == .livre ? "Descartar a sessão livre?" : "Abortar? A sessão será descartada."
    }

    // MARK: Sinal

    private func signal() {
        UIAccessibility.post(notification: .announcement, argument: "Sinal")
        if reduceMotion {
            flash = 0.35
            withAnimation(.easeOut(duration: 0.6)) { flash = 0 }
            return
        }
        flash = 0.7
        bump = true
        ripple = 0
        rippleOpacity = 0.9
        withAnimation(.easeOut(duration: 0.55)) { flash = 0 }
        withAnimation(PF.Motion.bouncy) { bump = false }
        withAnimation(.easeOut(duration: 1.1)) {
            ripple = 1
            rippleOpacity = 0
        }
    }
}

/// Botões da tela escura da sessão.
struct PaloStageButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: PF.Radius.button, style: .continuous)
        return configuration.label
            .pfText(.headline, weight: .semibold)
            .foregroundColor(prominent ? PF.stage : PF.stageInk)
            .frame(minHeight: 54)
            .padding(.horizontal, PF.Space.l)
            .background(prominent ? PF.stageInk : Color.clear, in: shape)
            .overlay(shape.stroke(prominent ? Color.clear : PF.stageLine, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(PF.Motion.press, value: configuration.isPressed)
    }
}
