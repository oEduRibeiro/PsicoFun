import SwiftUI
import UIKit

#if targetEnvironment(simulator)
/// Telas de demonstração para capturas automáticas (só no Simulador; nunca no aparelho).
///
/// Uso: abrir o app com `-PFDemoScreen <tela>`. Telas: prep, session, entry, result, history,
/// hr, bands, settings, stats. Os dados de exemplo só existem no Simulador.
enum PFDemo {
    static var screen: String? { UserDefaults.standard.string(forKey: "PFDemoScreen") }

    static func run(on root: UIViewController, engine: PaloSessionEngine, store: PaloStore,
                    psicoStore: PsicoStore, selectMode: (Int) -> Void) {
        guard let screen = screen else { return }
        store.replaceAll(sampleRecords())
        let records = store.records(for: .teste)
        if screen.hasPrefix("psico-") { seedPsico(psicoStore) }
        switch screen {
        case "psico-home":
            selectMode(0)
        case "psico-stats":
            present(NavigationStack { PsicoStatsView(store: psicoStore, nav: PsicoNav()) }, on: root)
        case "psico-setup":
            present(NavigationStack { PsicoSetupView(store: psicoStore, nav: PsicoNav(), mode: "livre") }, on: root)
        case "psico-quiz":
            _ = psicoStore.newSession(PsicoConfig(mode: "livre", fams: nil, lvl: 5, n: 20))
            psicoStore.ensureCurrentItem()
            present(PsicoQuizView(store: psicoStore, nav: PsicoNav()), on: root)
        case "psico-explanation":
            let s = psicoStore.newSession(PsicoConfig(mode: "livre", fams: ["mat"], lvl: 5, n: 20))
            if let it = psicoStore.item(s, 0) {
                let wrong = (it.answer + 1) % max(1, it.options.count)
                let a = psicoStore.record(s, 0, c: wrong, ms: 14_000)
                present(PsicoExplanationSheet(item: it, answer: a, isLast: false, onClose: {}, onNext: {}), on: root)
            }
        case "psico-result":
            if let id = psicoStore.db.sessions.last?.id {
                present(NavigationStack { PsicoResultView(store: psicoStore, nav: PsicoNav(), sessionId: id) }, on: root)
            }
        case "live":
            present(PaloActivityPreview(), on: root)
        case "prep":
            UserDefaults.standard.set(PaloMode.teste.rawValue, forKey: PaloKeys.mode)
            selectMode(1)
        case "session":
            selectMode(1)
            engine.start(mode: .teste, config: .init(sound: false, vibration: false, notificationFallback: false))
        case "entry":
            present(NavigationStack { PaloEntryView(engine: engine, store: store, cycles: 5) }, on: root)
        case "result":
            if let r = records.first {
                present(NavigationStack { PaloResultView(record: r, store: store, onClose: {}) }, on: root)
            }
        case "hr":
            if let r = records.first, let hr = r.heartRate {
                let prev = Array(records.dropFirst())
                present(NavigationStack {
                    PFScreen { PaloHRCard(heartRate: hr, previous: prev) }
                        .navigationTitle("Resultado · Teste")
                        .navigationBarTitleDisplayMode(.inline)
                }, on: root)
            }
        case "history":
            present(NavigationStack { PaloHistoryView(store: store, initialMode: .teste) }, on: root)
        case "bands":
            present(NavigationStack { PaloBandsView() }, on: root)
        case "settings":
            present(NavigationStack { PsicoSettingsView(store: psicoStore, paloStore: store) }, on: root)
        case "stats":
            present(NavigationStack { PsicoStatsView(store: psicoStore, nav: PsicoNav()) }, on: root)
        default:
            break
        }
    }

    private static func present<V: View>(_ view: V, on root: UIViewController) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let vc = UIHostingController(rootView: view)
            vc.modalPresentationStyle = .fullScreen
            vc.view.backgroundColor = Theme.background
            root.present(vc, animated: false)
        }
    }

    /// Responde algumas sessões de verdade (com o motor) para ter histórico no Psicotécnico.
    private static func seedPsico(_ store: PsicoStore) {
        guard store.db.sessions.isEmpty else { return }
        let fams: [[String]?] = [nil, nil, ["mat", "seq"], nil]
        for (k, f) in fams.enumerated() {
            _ = store.newSession(PsicoConfig(mode: k == 2 ? "rampa" : "livre", fams: f, lvl: 3 + k, from: 2, to: 7, n: 12))
            for i in 0..<12 {
                store.ensureCurrentItem()
                guard let s = store.current, let it = store.item(s, s.idx) else { break }
                let miss = (i * 7 + k) % 4 == 0
                let c = miss ? (it.answer + 1) % max(1, it.options.count) : it.answer
                store.lockAnswer(c, ms: Double(8_000 + (i * 1_700) % 9_000), timeout: false)
                if i < 11 { store.mutateCurrent { $0.idx += 1 } }
            }
            _ = store.finish(early: false)
        }
    }

    private static func sampleRecords() -> [PaloRecord] {
        let now = Date()
        let day: TimeInterval = 86_400
        let tests: [[Int]] = [[118, 124, 121, 117, 120], [126, 131, 128, 122, 127], [129, 134, 126, 131, 130],
                              [133, 139, 135, 104, 136], [138, 142, 140, 137, 141]]
        var out: [PaloRecord] = []
        for (i, c) in tests.enumerated() {
            let date = now.addingTimeInterval(-Double(tests.count - i) * day * 2)
            let hr: PaloHeartRate? = i >= 2 ? sampleHR(base: 84 + i * 2, partialAt: i == tests.count - 1 ? 3 : nil,
                                                       gapAt: i == tests.count - 1 ? 4 : nil) : nil
            out.append(PaloRecord(date: date, mode: .teste, counts: c, soundOn: true, vibrationOn: i % 2 == 0,
                                  note: i == tests.count - 1 ? "Lápis novo, dormi bem." : "",
                                  maxBeepDeviationMs: 3.2, heartRate: hr))
        }
        out.append(PaloRecord(date: now.addingTimeInterval(-day), mode: .treino, counts: [112, 119, 116],
                              soundOn: true, vibrationOn: true, note: "", maxBeepDeviationMs: 2.1))
        return out
    }

    private static func sampleHR(base: Int, partialAt: Int?, gapAt: Int?) -> PaloHeartRate {
        let deltas: [Int] = [0, 4, 7, 9, 11]
        let cycles: [PaloHRCycle] = deltas.indices.map { k in
            if k == gapAt { return PaloHRCycle(mean: nil, min: nil, max: nil, coverage: 0, samples: 0) }
            let m = base + deltas[k]
            let partial = k == partialAt
            return PaloHRCycle(mean: Double(m) + 0.4, min: m - 4, max: m + 5, coverage: partial ? 0.42 : 0.97,
                               samples: partial ? 25 : 58)
        }
        return PaloHeartRate(deviceName: "Garmin Forerunner", cycles: cycles)
    }
}

/// Prévia da Live Activity (tela bloqueada e Dynamic Island) nas três fases.
struct PaloActivityPreview: View {
    private func state(_ mode: PaloMode, cycle: Int) -> PaloActivityAttributes.ContentState {
        let start = Date().addingTimeInterval(-Double(cycle - 1) * 60 - 23)
        let interval: ClosedRange<Date>? = mode == .teste ? nil
            : (mode == .treino ? start...start.addingTimeInterval(180) : start...start.addingTimeInterval(12 * 3600))
        return .init(phase: mode.rawValue, phaseTitle: mode.title, currentCycle: cycle,
                     totalCycles: mode.cycles ?? 0, phaseInterval: interval, finished: false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Live Activity").pfText(.largeTitle)
                ForEach([(PaloMode.treino, 2), (PaloMode.teste, 2), (PaloMode.livre, 4)], id: \.0) { m, c in
                    let st = state(m, cycle: c)
                    Text(m == .teste ? "Teste: sem tempo, só o ciclo" : "\(m.title): com cronômetro").pfText(.eyebrow).foregroundColor(PF.muted)
                    PaloLockScreenView(state: st)
                        .background(PaloActivityStyle.background.opacity(0.88), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    HStack(spacing: 10) {
                        island(compact: st)
                        Spacer()
                    }
                }
                Text("Dynamic Island aberta (Teste)").pfText(.eyebrow).foregroundColor(PF.muted)
                expanded(state(.teste, cycle: 3))
            }
            .padding(16)
        }
        .background(LinearGradient(colors: [Color(red: 0.25, green: 0.3, blue: 0.45), Color(red: 0.55, green: 0.45, blue: 0.5)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private func island(compact st: PaloActivityAttributes.ContentState) -> some View {
        HStack {
            Image(systemName: PaloActivityStyle.icon).foregroundColor(PaloActivityStyle.accent)
            Spacer(minLength: 70)
            PaloTimeOrCycle(state: st, compact: true)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundColor(PaloActivityStyle.ink)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Color.black, in: Capsule())
    }

    private func expanded(_ st: PaloActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(st.phaseTitle, systemImage: PaloActivityStyle.icon)
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(PaloActivityStyle.ink)
                Spacer()
                PaloTimeOrCycle(state: st, compact: false)
                    .font(.system(size: 22, weight: .bold).monospacedDigit()).foregroundColor(PaloActivityStyle.ink)
            }
            Text(PaloText.cycleLong(st)).font(.system(size: 15, weight: .medium)).foregroundColor(PaloActivityStyle.muted)
            PaloActivityCycleBar(state: st)
        }
        .padding(20)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
    }
}
#endif
