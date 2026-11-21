import Foundation
import JavaScriptCore

/// Motor de geração de questões.
///
/// O gerador e o solucionador são os mesmos do app original (Engine/engine.js),
/// rodando no JavaScriptCore só como lógica — sem WebView e sem HTML. Toda a
/// interface é SwiftUI. Assim cada semente continua gerando exatamente a mesma
/// questão de antes, e a revisão de sessões antigas mostra o que foi visto.
final class PsicoEngine {
    static let shared = PsicoEngine()

    private let queue = DispatchQueue(label: "psicofun.engine", qos: .userInitiated)
    private var context: JSContext?
    private var makeFn: JSValue?
    private var keyLabelFn: JSValue?
    private var whereKeyFn: JSValue?

    private let lock = NSLock()
    private var cache: [String: PsicoItem] = [:]
    private var labels: [String: String] = [:]
    private var wheres: [String: [(String, Int)]] = [:]

    private init() {}

    /// Carrega o motor em segundo plano (chamado ao abrir o app).
    func warmUp() {
        queue.async { [self] in setupIfNeeded() }
    }

    private func setupIfNeeded() {
        guard context == nil else { return }
        guard let ctx = JSContext() else { return }
        ctx.exceptionHandler = { _, exc in
            NSLog("PsicoEngine JS: %@", exc?.toString() ?? "?")
        }
        if let url = Bundle.main.url(forResource: "engine", withExtension: "js", subdirectory: "Engine")
            ?? Bundle.main.url(forResource: "engine", withExtension: "js"),
           let src = try? String(contentsOf: url, encoding: .utf8) {
            ctx.evaluateScript(src, withSourceURL: url)
        }
        ctx.evaluateScript("""
        var PFN = {
          make: function(f, l, s, p) { try { return JSON.stringify(PV.make(f, l, s, p && p.length ? p : undefined)); } catch (e) { return null; } },
          keyLabel: function(k) { return PV.keyLabel(k); },
          whereKey: function(k) { return JSON.stringify(PV.whereKey(k)); }
        };
        """)
        let pfn = ctx.objectForKeyedSubscript("PFN")
        makeFn = pfn?.objectForKeyedSubscript("make")
        keyLabelFn = pfn?.objectForKeyedSubscript("keyLabel")
        whereKeyFn = pfn?.objectForKeyedSubscript("whereKey")
        context = ctx
    }

    private static func cacheKey(_ s: PsicoItemSpec) -> String {
        "\(s.fam)|\(s.lvl)|\(s.seed)|\((s.prefer ?? []).joined(separator: ","))"
    }

    private func cached(_ key: String) -> PsicoItem? {
        lock.lock(); defer { lock.unlock() }
        return cache[key]
    }

    private func store(_ item: PsicoItem, _ key: String) {
        lock.lock(); defer { lock.unlock() }
        if cache.count > 400 { cache.removeAll(keepingCapacity: true) }
        cache[key] = item
    }

    /// Gera (ou devolve do cache) a questão de uma semente. Rápido: ~1 ms.
    func item(_ spec: PsicoItemSpec) -> PsicoItem? {
        let key = Self.cacheKey(spec)
        if let it = cached(key) { return it }
        return queue.sync { generate(spec, key) }
    }

    /// Gera a questão em segundo plano, para a próxima tela abrir sem espera.
    func prefetch(_ specs: [PsicoItemSpec]) {
        queue.async { [self] in
            for s in specs {
                let key = Self.cacheKey(s)
                if cached(key) == nil { _ = generate(s, key) }
            }
        }
    }

    func isCached(_ spec: PsicoItemSpec) -> Bool { cached(Self.cacheKey(spec)) != nil }

    /// Só na fila do motor.
    private func generate(_ spec: PsicoItemSpec, _ key: String) -> PsicoItem? {
        if let it = cached(key) { return it }
        setupIfNeeded()
        let prefer: Any = spec.prefer ?? NSNull()
        guard let fn = makeFn,
              let json = fn.call(withArguments: [spec.fam, spec.lvl, NSNumber(value: spec.seed), prefer]),
              json.isString,
              let data = json.toString().data(using: .utf8) else { return nil }
        do {
            let item = try JSONDecoder().decode(PsicoItem.self, from: data)
            store(item, key)
            return item
        } catch {
            NSLog("PsicoEngine decode: %@", String(describing: error))
            return nil
        }
    }

    /// Nome legível de uma regra ("Rotação · progressão").
    func keyLabel(_ k: String) -> String {
        lock.lock()
        if let l = labels[k] { lock.unlock(); return l }
        lock.unlock()
        let l: String = queue.sync {
            setupIfNeeded()
            return keyLabelFn?.call(withArguments: [k])?.toString() ?? k
        }
        lock.lock(); labels[k] = l; lock.unlock()
        return l
    }

    /// Em que famílias / nível mínimo uma regra pode aparecer (para o modo Ponto fraco).
    func whereKey(_ k: String) -> [(String, Int)] {
        lock.lock()
        if let w = wheres[k] { lock.unlock(); return w }
        lock.unlock()
        let w: [(String, Int)] = queue.sync {
            setupIfNeeded()
            guard let s = whereKeyFn?.call(withArguments: [k])?.toString(),
                  let data = s.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
            return arr.compactMap { e in
                guard e.count == 2, let f = e[0] as? String, let l = e[1] as? NSNumber else { return nil }
                return (f, l.intValue)
            }
        }
        lock.lock(); wheres[k] = w; lock.unlock()
        return w
    }
}
