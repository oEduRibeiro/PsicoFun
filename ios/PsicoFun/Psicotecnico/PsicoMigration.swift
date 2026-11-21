import Foundation
import WebKit

/// Migração única dos dados da versão em WebView.
///
/// O app antigo gravava o estado em dois lugares: no arquivo psicofun-state.json
/// (que a versão nativa continua lendo, no mesmo formato) e no localStorage do
/// WebView, como reserva. Na primeira abertura da versão nativa, lemos o
/// localStorage uma única vez e, se ele tiver um estado mais recente que o do
/// arquivo (por exemplo, se o app foi fechado antes de terminar de gravar),
/// usamos o mais recente. Depois disso o WebView não é mais usado.
final class PsicoMigration: NSObject, WKScriptMessageHandler, WKURLSchemeHandler {
    private static let doneKey = "pf.psico.webStorageMigrated"
    private static var running: PsicoMigration?

    private var webView: WKWebView?
    private var completion: ((String?) -> Void)?
    private var timeout: DispatchWorkItem?

    static func runIfNeeded(store: PsicoStore) {
        guard !UserDefaults.standard.bool(forKey: doneKey), running == nil else { return }
        let m = PsicoMigration()
        running = m
        m.readLocalStorage { text in
            defer {
                running = nil
            }
            guard let text = text else { return } // sem resposta: tenta de novo na próxima abertura
            UserDefaults.standard.set(true, forKey: doneKey)
            guard !text.isEmpty, let data = text.data(using: .utf8),
                  let web = try? JSONDecoder().decode(PsicoDB.self, from: data), web.v == 1 else { return }
            let local = store.db
            let webSaved = web.saved ?? 0, localSaved = local.saved ?? 0
            let localEmpty = local.sessions.isEmpty && local.current == nil
            if webSaved > localSaved || (localEmpty && (!web.sessions.isEmpty || web.current != nil)) {
                store.adopt(web)
                NSLog("PsicoMigration: estado do WebView adotado (%d sessões)", web.sessions.count)
            }
        }
    }

    /// Carrega uma página mínima na mesma origem do app antigo (psicofun://app) e lê o localStorage.
    private func readLocalStorage(_ done: @escaping (String?) -> Void) {
        completion = done
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.setURLSchemeHandler(self, forURLScheme: "psicofun")
        config.userContentController.add(self, name: "pf")
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView = wv
        wv.load(URLRequest(url: URL(string: "psicofun://app/index.html")!))
        let t = DispatchWorkItem { [weak self] in self?.finish(nil) }
        timeout = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: t)
    }

    private func finish(_ text: String?) {
        guard let c = completion else { return }
        completion = nil
        timeout?.cancel()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "pf")
        webView?.stopLoading()
        webView = nil
        c(text)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        finish((message.body as? String) ?? "")
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8"></head><body><script>
        var t = null; try { t = localStorage.getItem('psicovisual.v1'); } catch (e) {}
        window.webkit.messageHandlers.pf.postMessage(t || '');
        </script></body></html>
        """
        let data = Data(html.utf8)
        let url = urlSchemeTask.request.url ?? URL(string: "psicofun://app/index.html")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/html; charset=utf-8",
                                                      "Content-Length": String(data.count)])!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
