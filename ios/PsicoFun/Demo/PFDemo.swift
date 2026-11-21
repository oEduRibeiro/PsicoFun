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
                    psicoStore: PsicoStore, selectPalografico: () -> Void) {
        guard let screen = screen else { return }
        store.replaceAll(sampleRecords())
        let records = store.records(for: .teste)
        switch screen {
        case "prep":
            UserDefaults.standard.set(PaloMode.teste.rawValue, forKey: PaloKeys.mode)
            selectPalografico()
        case "session":
            selectPalografico()
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
#endif
