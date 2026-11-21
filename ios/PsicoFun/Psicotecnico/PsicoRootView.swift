import SwiftUI
import UIKit

enum PsicoTab: Hashable { case home, stats, settings }

enum PsicoRoute: Hashable {
    case setup(String)
    case result(String)
}

/// Rascunho da tela de configuração (fica guardado enquanto o modo não muda).
struct PsicoSetupDraft: Equatable {
    var mode: String
    var fams: Set<String> = Set(PsicoText.famKeys)
    var lvl = 3
    var from = 1
    var to = 10
    var n = 20
    var minutes = 20
    var keys: Set<String> = []
    var weak: [PsicoKeyStat] = []
    var customN = false
    var customMinutes = false
}

/// Navegação do modo Psicotécnico.
final class PsicoNav: ObservableObject {
    @Published var tab: PsicoTab = .home
    @Published var homePath: [PsicoRoute] = []
    @Published var statsPath: [PsicoRoute] = []
    @Published var quizShown = false
    var draft: PsicoSetupDraft?

    func openSetup(_ mode: String) {
        tab = .home
        homePath = [.setup(mode)]
    }

    func openResult(_ id: String) {
        tab = .stats
        statsPath = [.result(id)]
    }
}

/// Raiz do Psicotécnico: abas nativas (Treinar, Desempenho, Ajustes) e a tela da questão por cima.
struct PsicoRootView: View {
    @ObservedObject var store: PsicoStore
    let paloStore: PaloStore
    @StateObject private var nav = PsicoNav()

    var body: some View {
        ZStack {
            TabView(selection: tabBinding) {
                NavigationStack(path: $nav.homePath) {
                    PsicoHomeView(store: store, nav: nav)
                        .navigationDestination(for: PsicoRoute.self) { destination($0) }
                }
                .tabItem { Label("Treinar", systemImage: "square.grid.2x2") }
                .tag(PsicoTab.home)

                NavigationStack(path: $nav.statsPath) {
                    PsicoStatsView(store: store, nav: nav)
                        .navigationDestination(for: PsicoRoute.self) { destination($0) }
                }
                .tabItem { Label("Desempenho", systemImage: "chart.bar") }
                .tag(PsicoTab.stats)

                NavigationStack {
                    PsicoSettingsView(store: store, paloStore: paloStore)
                }
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .tag(PsicoTab.settings)
            }
            .tint(PF.acc)

            if nav.quizShown, store.current != nil {
                PsicoQuizView(store: store, nav: nav)
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.9), value: nav.quizShown)
        .overlay(alignment: .bottom) {
            if let t = store.toast {
                Text(t)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PF.paper)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(PF.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, nav.quizShown ? 100 : 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .onAppear { PsicoEngine.shared.warmUp() }
    }

    private var tabBinding: Binding<PsicoTab> {
        Binding(get: { nav.tab }, set: { new in
            if new != nav.tab { Haptics.play("selection") }
            nav.tab = new
        })
    }

    @ViewBuilder
    private func destination(_ r: PsicoRoute) -> some View {
        switch r {
        case .setup(let mode): PsicoSetupView(store: store, nav: nav, mode: mode)
        case .result(let id): PsicoResultView(store: store, nav: nav, sessionId: id)
        }
    }
}
