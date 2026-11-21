import UIKit
import WebKit

/// Tela única do app: o motor de questões roda empacotado no app (offline),
/// e a parte nativa cuida de armazenamento, vibração (háptico), compartilhamento
/// e gestos do sistema.
final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private let store = Store()

    override func loadView() {
        let config = WKWebViewConfiguration()
        let content = WKUserContentController()

        // Entrega os dados salvos ao JS antes de qualquer script da página rodar.
        let saved = store.load()
        let literal = Self.jsStringLiteral(saved)
        content.addUserScript(WKUserScript(
            source: "window.__PF_DB=\(literal);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true))
        content.add(WeakMessageHandler(self), name: "pf")

        config.userContentController = content
        config.setURLSchemeHandler(LocalSchemeHandler(), forURLScheme: LocalSchemeHandler.scheme)
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.dataDetectorTypes = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = Theme.background
        webView.scrollView.backgroundColor = Theme.background
        webView.scrollView.contentInsetAdjustmentBehavior = .never // o CSS usa env(safe-area-inset-*)
        webView.scrollView.keyboardDismissMode = .interactive
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        self.webView = webView
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        webView.load(URLRequest(url: URL(string: "\(LocalSchemeHandler.scheme)://app/index.html")!))
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    // MARK: - Mensagens do JS

    fileprivate func handle(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "save":
            if let text = body["data"] as? String { store.save(text) }
        case "haptic":
            Haptics.play(body["data"] as? String ?? "light")
        case "share":
            if let text = body["data"] as? String { shareBackup(text) }
        default:
            break
        }
    }

    private func shareBackup(_ text: String) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("psicofun-backup-\(fmt.string(from: Date())).json")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return
        }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        present(vc, animated: true)
    }

    // MARK: - Navegação: links externos abrem no Safari

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme != LocalSchemeHandler.scheme, scheme != "about", scheme != "blob", scheme != "data" {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    // MARK: - Diálogos JS (caso algum seja usado)

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    // MARK: - Util

    private static func jsStringLiteral(_ text: String?) -> String {
        guard let text = text,
              let data = try? JSONSerialization.data(withJSONObject: [text], options: []),
              var json = String(data: data, encoding: .utf8) else { return "null" }
        // [ "..." ] -> "..."
        json.removeFirst()
        json.removeLast()
        return json
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}

/// Evita o ciclo de referência entre WKUserContentController e o controller.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WebViewController?
    init(_ target: WebViewController) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.handle(message)
    }
}
