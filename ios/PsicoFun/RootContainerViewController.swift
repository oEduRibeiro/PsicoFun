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
        vc.view.backgroundColor = .systemGroupedBackground
        return vc
    }()

    private let bar = UIView()
    private let segmented = UISegmentedControl(items: ["Psicotécnico", "Palográfico"])
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
        segmented.translatesAutoresizingMaskIntoConstraints = false
        segmented.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        content.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(content)
        view.addSubview(bar)
        bar.addSubview(segmented)

        contentBelowBar = content.topAnchor.constraint(equalTo: bar.bottomAnchor)
        contentAtTop = content.topAnchor.constraint(equalTo: view.topAnchor)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            segmented.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            segmented.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -8),
            segmented.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            segmented.leadingAnchor.constraint(greaterThanOrEqualTo: bar.layoutMarginsGuide.leadingAnchor),
            segmented.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            segmented.widthAnchor.constraint(equalTo: bar.widthAnchor, constant: -32).withPriority(.defaultHigh),
            contentBelowBar,
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        embed(psicoController)
        embed(paloController)

        let saved = Mode(rawValue: UserDefaults.standard.integer(forKey: Self.modeKey)) ?? .psicotecnico
        mode = saved
        segmented.selectedSegmentIndex = saved.rawValue
        showMode(saved)

        PsicoEngine.shared.warmUp()
        PsicoMigration.runIfNeeded(store: psicoStore)

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

    @objc private func segmentChanged() {
        let new = Mode(rawValue: segmented.selectedSegmentIndex) ?? .psicotecnico
        guard new != mode else { return }
        mode = new
        showMode(new)
        Haptics.play("selection")
    }

    private func showMode(_ mode: Mode) {
        psicoController.view.isHidden = mode != .psicotecnico
        paloController.view.isHidden = mode != .palografico
        view.endEditing(true)
    }

    /// Esconde o seletor (e a barra de status) durante a sessão; os toggles ficam travados.
    private func updateChrome(animated: Bool) {
        segmented.isEnabled = !sessionRunning
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

private extension NSLayoutConstraint {
    func withPriority(_ p: UILayoutPriority) -> NSLayoutConstraint {
        priority = p
        return self
    }
}
