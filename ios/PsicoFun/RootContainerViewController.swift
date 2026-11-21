import Combine
import SwiftUI
import UIKit

/// Tela raiz: seletor no topo alternando entre o Psicotécnico e o Palográfico (ambos em SwiftUI).
///
/// As duas telas ficam vivas o tempo todo (só uma visível), então trocar de modo não
/// perde o estado de nenhuma delas. Durante uma sessão do Palográfico o seletor e a
/// barra de status somem (a barra de status mostra o relógio, o que revelaria o tempo no Teste).
final class RootContainerViewController: UIViewController {
    enum Mode: Int {
        case psicotecnico = 0
        case palografico = 1
    }

    private static let modeKey = "pf.rootMode"

    private let engine = PaloSessionEngine()
    private let store = PaloStore()
    private let psicoStore = PsicoStore()
    private lazy var psicoController: UIHostingController<PsicoRootView> = {
        let vc = UIHostingController(rootView: PsicoRootView(store: psicoStore, paloStore: store))
        vc.view.backgroundColor = Theme.background
        return vc
    }()
    private lazy var paloController: UIHostingController<PalograficoRootView> = {
        let vc = UIHostingController(rootView: PalograficoRootView(engine: engine, store: store))
        vc.view.backgroundColor = Theme.background
        return vc
    }()

    private let bar = UIView()
    private let switcherModel = RootModeModel()
    private lazy var switcherHost: UIHostingController<PFModeSwitcher> = {
        let vc = UIHostingController(rootView: PFModeSwitcher(model: switcherModel))
        vc.view.backgroundColor = .clear
        vc.sizingOptions = .intrinsicContentSize
        return vc
    }()
    private let content = UIView()
    private var contentBelowBar: NSLayoutConstraint!
    private var contentAtTop: NSLayoutConstraint!
    private var cancellables = Set<AnyCancellable>()

    private var mode: Mode = .psicotecnico {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }

    private var sessionRunning = false {
        didSet {
            guard oldValue != sessionRunning else { return }
            updateChrome(animated: true)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        PaloKeys.registerDefaults()
        view.backgroundColor = Theme.background

        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.backgroundColor = Theme.background
        let switcher = switcherHost.view!
        switcher.translatesAutoresizingMaskIntoConstraints = false
        switcher.setContentHuggingPriority(.required, for: .vertical)
        switcher.setContentCompressionResistancePriority(.required, for: .vertical)
        content.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(content)
        view.addSubview(bar)
        addChild(switcherHost)
        bar.addSubview(switcher)
        switcherHost.didMove(toParent: self)

        contentBelowBar = content.topAnchor.constraint(equalTo: bar.bottomAnchor)
        contentAtTop = content.topAnchor.constraint(equalTo: view.topAnchor)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            switcher.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            switcher.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            switcher.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            switcher.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            contentBelowBar,
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        embed(psicoController)
        embed(paloController)

        let saved = Mode(rawValue: UserDefaults.standard.integer(forKey: Self.modeKey)) ?? .psicotecnico
        mode = saved
        switcherModel.mode = saved.rawValue
        switcherModel.onChange = { [weak self] raw in self?.modeSelected(raw) }
        showMode(saved)

        PsicoEngine.shared.warmUp()
        PsicoMigration.runIfNeeded(store: psicoStore)

        #if targetEnvironment(simulator)
        PFDemo.run(on: self, engine: engine, store: store, psicoStore: psicoStore) { [weak self] in
            self?.switcherModel.mode = Mode.palografico.rawValue
            self?.modeSelected(Mode.palografico.rawValue)
        }
        #endif

        engine.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in self?.sessionRunning = running }
            .store(in: &cancellables)
    }

    override var prefersStatusBarHidden: Bool { sessionRunning }
    override var preferredStatusBarStyle: UIStatusBarStyle { .default }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    private func embed(_ child: UIViewController) {
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: content.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        child.didMove(toParent: self)
    }

    private func modeSelected(_ raw: Int) {
        let new = Mode(rawValue: raw) ?? .psicotecnico
        guard new != mode else { return }
        mode = new
        showMode(new)
    }

    private func showMode(_ mode: Mode) {
        psicoController.view.isHidden = mode != .psicotecnico
        paloController.view.isHidden = mode != .palografico
        view.endEditing(true)
    }

    /// Esconde o seletor (e a barra de status) durante a sessão; os toggles ficam travados.
    private func updateChrome(animated: Bool) {
        switcherHost.view.isUserInteractionEnabled = !sessionRunning
        if sessionRunning {
            contentBelowBar.isActive = false
            contentAtTop.isActive = true
        } else {
            contentAtTop.isActive = false
            contentBelowBar.isActive = true
        }
        let changes = {
            self.bar.alpha = self.sessionRunning ? 0 : 1
            self.setNeedsStatusBarAppearanceUpdate()
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.25, animations: changes)
        } else {
            changes()
        }
        view.bringSubviewToFront(sessionRunning ? content : bar)
    }
}

/// Estado do seletor do topo (compartilhado entre o UIKit e a SwiftUI).
final class RootModeModel: ObservableObject {
    @Published var mode = 0
    var onChange: ((Int) -> Void)?

    func select(_ raw: Int) {
        guard raw != mode else { return }
        mode = raw
        onChange?(raw)
    }
}

/// Seletor do topo: Psicotécnico | Palográfico, no mesmo controle segmentado do app.
struct PFModeSwitcher: View {
    @ObservedObject var model: RootModeModel

    private let options: [PFSegmented<Int>.Option] = [
        PFSegmented<Int>.Option(value: 0, title: "Psicotécnico", icon: "square.grid.3x3.fill"),
        PFSegmented<Int>.Option(value: 1, title: "Palográfico", icon: "pencil.line"),
    ]

    var body: some View {
        PFSegmented<Int>(options: options, selection: Binding(get: { model.mode }, set: { model.select($0) }))
            .frame(maxWidth: 440)
            .padding(.horizontal, PF.Space.screen)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(PF.bg)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Modo do app")
    }
}
