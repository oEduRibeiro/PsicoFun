import UIKit
import WebKit
import UniformTypeIdentifiers

/// Serve os arquivos da pasta "Web" do bundle em psicofun://app/...
/// Uma origem fixa mantém o localStorage estável e tudo funciona offline.
final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "psicofun"

    private lazy var root: URL? = Bundle.main.resourceURL?.appendingPathComponent("Web", isDirectory: true)

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let root = root else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let fileURL = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        guard fileURL.path.hasPrefix(root.standardizedFileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let headers = [
            "Content-Type": mime.hasPrefix("text/") ? "\(mime); charset=utf-8" : mime,
            "Content-Length": String(data.count),
            "Cache-Control": "no-cache",
        ]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

/// Guarda o estado do app (sessões, ajustes, nível) num arquivo em Application Support.
/// É a cópia principal; o localStorage do WebView fica como reserva.
final class Store {
    private let queue = DispatchQueue(label: "psicofun.store", qos: .utility)
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("psicofun-state.json")
    }()

    func load() -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    func save(_ text: String) {
        queue.async { [url] in
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

enum Haptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()
    private static let light = UIImpactFeedbackGenerator(style: .light)

    static func play(_ kind: String) {
        switch kind {
        case "selection": selection.selectionChanged()
        case "success": notification.notificationOccurred(.success)
        case "error": notification.notificationOccurred(.error)
        case "warning": notification.notificationOccurred(.warning)
        default: light.impactOccurred()
        }
    }
}
