import Foundation
import SwiftUI

/// Estatística de uma regra (chave) nas respostas.
struct PsicoKeyStat: Identifiable, Equatable {
    var id: String { k }
    let k: String
    var seen: Int
    var err: Int
    var rate: Double { seen > 0 ? Double(err) / Double(seen) : 0 }
    var score: Double { (Double(err) + 0.5) / (Double(seen) + 2) }
}

struct PsicoFamStat: Identifiable, Equatable {
    var id: String { f }
    let f: String
    let n: Int
    let ok: Int
}

/// Números agregados do histórico, recalculados só quando o histórico muda.
struct PsicoLevelStat: Equatable { let level: Int; let n: Int; let ok: Int }
struct PsicoRecent: Equatable { let id: String; let pct: Int }

struct PsicoSummary: Equatable {
    var total = 0
    var ok = 0
    var totalMs: Double = 0
    var weak: [PsicoKeyStat] = []        // até 8, para Desempenho
    var fams: [PsicoFamStat] = []
    var levels: [PsicoLevelStat] = []
    var recent: [PsicoRecent] = []
}

enum PsicoStats {
    static func keyStats(_ ans: [PsicoAnswer]) -> [PsicoKeyStat] {
        var m: [String: PsicoKeyStat] = [:]
        var order: [String] = []
        func touch(_ k: String) { if m[k] == nil { m[k] = PsicoKeyStat(k: k, seen: 0, err: 0); order.append(k) } }
        for a in ans {
            let keys = a.keys ?? []
            for k in keys { touch(k); m[k]!.seen += 1 }
            for k in a.err ?? [] {
                touch(k); m[k]!.err += 1
                if !keys.contains(k) { m[k]!.seen += 1 }
            }
        }
        return order.compactMap { m[$0] }
    }

    /// Pontos fracos: regras com erro que o gerador consegue treinar.
    static func weakKeys(_ ans: [PsicoAnswer], _ n: Int) -> [PsicoKeyStat] {
        let ks = keyStats(ans).filter { $0.err > 0 && $0.k != "tempo" && !PsicoEngine.shared.whereKey($0.k).isEmpty }
        return Array(stableSorted(ks) { a, b in a.score != b.score ? a.score > b.score : a.err > b.err }.prefix(n))
    }

    static func famStats(_ ans: [PsicoAnswer]) -> [PsicoFamStat] {
        PsicoText.famKeys.map { f in
            let x = ans.filter { $0.fam == f }
            return PsicoFamStat(f: f, n: x.count, ok: x.filter(\.ok).count)
        }
    }

    static func stableSorted<T>(_ a: [T], by less: (T, T) -> Bool) -> [T] {
        a.enumerated().sorted { l, r in
            if less(l.element, r.element) { return true }
            if less(r.element, l.element) { return false }
            return l.offset < r.offset
        }.map(\.element)
    }
}

/// Estado do modo Psicotécnico: dados salvos, sessão em andamento e histórico.
final class PsicoStore: ObservableObject {
    @Published private(set) var db: PsicoDB
    @Published private(set) var summary = PsicoSummary()
    @Published private(set) var homeWeak: [PsicoKeyStat] = []
    @Published var toast: String?

    private let url: URL
    private let ioQueue = DispatchQueue(label: "psicofun.store", qos: .utility)
    private var pendingWrite: Data?
    private var writeScheduled = false
    private var toastWork: DispatchWorkItem?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("psicofun-state.json")
        var loaded = PsicoDB()
        if let data = try? Data(contentsOf: url),
           let d = try? JSONDecoder().decode(PsicoDB.self, from: data), d.v == 1 {
            loaded = d
        }
        loaded.v = 1
        db = loaded
        recomputeSummary()
    }

    var settings: PsicoSettings { db.settings }
    var current: PsicoSession? { db.current }

    // MARK: Persistência

    /// Grava o estado em segundo plano (a codificação também sai da tela principal).
    func save() {
        db.saved = (Date().timeIntervalSince1970 * 1000).rounded()
        let snapshot = db
        ioQueue.async { [weak self] in
            guard let self = self, let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: self.url, options: .atomic)
        }
    }

    /// Troca o estado inteiro (migração do WebView ou restauração de backup).
    func adopt(_ newDB: PsicoDB) {
        var d = newDB
        d.v = 1
        db = d
        save()
        recomputeSummary()
    }

    func updateSettings(_ f: (inout PsicoSettings) -> Void) {
        f(&db.settings)
        save()
    }

    func showToast(_ text: String) {
        toastWork?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { toast = text }
        let w = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.2)) { self?.toast = nil }
        }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: w)
    }

    // MARK: Estatísticas

    var allAnswers: [PsicoAnswer] { db.sessions.flatMap { $0.answers } }

    func recomputeSummary() {
        let ans = allAnswers
        var s = PsicoSummary()
        s.total = ans.count
        s.ok = ans.filter(\.ok).count
        s.totalMs = ans.reduce(0) { $0 + $1.ms }
        s.weak = Array(PsicoStats.stableSorted(PsicoStats.keyStats(ans).filter { $0.err > 0 }) { $0.score > $1.score }.prefix(8))
        s.fams = PsicoStats.famStats(ans).filter { $0.n > 0 }
        let last = ans.suffix(60)
        s.levels = (1...10).compactMap { L in
            let x = last.filter { $0.lvl == L }
            return x.isEmpty ? nil : PsicoLevelStat(level: L, n: x.count, ok: x.filter(\.ok).count)
        }
        s.recent = db.sessions.suffix(20).map { PsicoRecent(id: $0.id, pct: PsicoFormat.pct($0.answers.filter(\.ok).count, $0.answers.count)) }
        summary = s
        homeWeak = PsicoStats.weakKeys(ans, 3)
    }

    func session(id: String) -> PsicoSession? { db.sessions.first { $0.id == id } }

    // MARK: Sessão

    func fbOf(_ mode: String) -> String { PsicoText.mode(mode).fbEnd ? "end" : db.settings.feedback }

    func fbText(_ mode: String) -> String {
        let f = fbOf(mode)
        return PsicoText.fbText[f == "eye" && db.settings.showCorrect ? "eyeC" : f] ?? ""
    }

    static func randomSeed() -> Int { Int(UInt32.random(in: 0...UInt32.max)) }

    private static func newId() -> String {
        let ms = Int64(Date().timeIntervalSince1970 * 1000)
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        return String(ms, radix: 36) + String((0..<4).map { _ in chars.randomElement()! })
    }

    private static func famCycle(_ fams: [String], _ n: Int) -> [String] {
        var out: [String] = []
        while out.count < n { out += fams.shuffled() }
        return Array(out.prefix(n))
    }

    @discardableResult
    func newSession(_ c: PsicoConfig) -> PsicoSession {
        let n = c.n ?? 20
        let fams = (c.fams?.isEmpty == false ? c.fams! : PsicoText.famKeys)
        let lvl = c.lvl ?? 3
        var s = PsicoSession(id: Self.newId(), mode: c.mode, created: (Date().timeIntervalSince1970 * 1000).rounded(),
                             cfg: c, items: [], idx: 0, fb: fbOf(c.mode), n: n)
        switch c.mode {
        case "adapt":
            s.adapt = PsicoAdapt(lvl: lvl, streak: 0, hist: [])
            s.items.append(PsicoItemSpec(fam: fams.randomElement()!, lvl: lvl, seed: Self.randomSeed()))
        case "foco":
            let ks = c.keys ?? []
            for i in 0..<n where !ks.isEmpty {
                let k = ks[i % ks.count]
                let w = PsicoEngine.shared.whereKey(k)
                guard let pick = w.randomElement() else { continue }
                let (f, minL) = pick
                let l = min(10, max(minL, lvl + Int.random(in: 0...2) - 1))
                s.items.append(PsicoItemSpec(fam: f, lvl: l, seed: Self.randomSeed(), prefer: [k]))
            }
            s.items.shuffle()
            s.n = s.items.count
        default:
            let fs = Self.famCycle(fams, n)
            let from = c.from ?? 1, to = c.to ?? 10
            for i in 0..<n {
                let l = c.mode == "rampa"
                    ? Int((Double(from) + Double(to - from) * (n > 1 ? Double(i) / Double(n - 1) : 0)).rounded())
                    : lvl
                s.items.append(PsicoItemSpec(fam: fs[i], lvl: l, seed: Self.randomSeed()))
            }
        }
        if c.mode == "simulado" { s.limit = Double((c.minutes ?? 20) * 60000) }
        db.current = s
        save()
        PsicoEngine.shared.prefetch(Array(s.items.prefix(2)))
        return s
    }

    func discardCurrent() {
        db.current = nil
        save()
    }

    /// Garante que a questão atual existe (o Adaptativo cria uma por vez).
    func ensureCurrentItem() {
        guard var s = db.current, s.mode == "adapt", s.idx < s.n, s.idx >= s.items.count, let a = s.adapt else { return }
        let fams = s.cfg?.fams?.isEmpty == false ? s.cfg!.fams! : PsicoText.famKeys
        s.items.append(PsicoItemSpec(fam: fams.randomElement()!, lvl: a.lvl, seed: Self.randomSeed()))
        db.current = s
    }

    func item(_ s: PsicoSession, _ i: Int) -> PsicoItem? {
        guard i < s.items.count else { return nil }
        return PsicoEngine.shared.item(s.items[i])
    }

    func record(_ s: PsicoSession, _ i: Int, c: Int, ms: Double, timeout: Bool = false) -> PsicoAnswer? {
        guard let it = item(s, i) else { return nil }
        let ok = c == it.answer
        let err: [String] = ok ? [] : (c >= 0 ? it.options[c].errs : (timeout ? ["tempo"] : []))
        return PsicoAnswer(c: c, ok: ok, ms: ms, to: timeout, fam: it.fam, lvl: it.lvl, keys: it.keys, err: err)
    }

    func mutateCurrent(_ f: (inout PsicoSession) -> Void, persist: Bool = true) {
        guard var s = db.current else { return }
        f(&s)
        db.current = s
        if persist { save() }
    }

    /// Confirma a resposta da questão atual (modos de treino).
    @discardableResult
    func lockAnswer(_ c: Int, ms: Double, timeout: Bool) -> PsicoAnswer? {
        guard var s = db.current, s.answer(at: s.idx) == nil,
              let a = record(s, s.idx, c: c, ms: ms, timeout: timeout) else { return nil }
        s.setAnswer(a, at: s.idx)
        if s.mode == "adapt", var A = s.adapt {
            A.hist.append(s.items[s.idx].lvl)
            if a.ok {
                A.streak += 1
                if A.streak >= 2 { A.lvl = min(10, A.lvl + 1); A.streak = 0 }
            } else {
                A.lvl = max(1, A.lvl - 1); A.streak = 0
            }
            s.adapt = A
        }
        db.current = s
        save()
        return a
    }

    /// Encerra a sessão atual e guarda no histórico. Devolve o id para abrir o resultado.
    func finish(early: Bool) -> String? {
        guard var s = db.current else { return nil }
        if s.mode == "simulado" {
            for i in 0..<s.n where s.answer(at: i) == nil {
                s.setAnswer(record(s, i, c: -1, ms: 0), at: i)
            }
            s.ans = Array(s.ans.prefix(s.n))
        } else if early {
            let k = s.ans.filter { $0 != nil }.count
            s.items = Array(s.items.prefix(k))
            s.ans = Array(s.ans.prefix(k))
            s.n = k
        } else {
            s.items = Array(s.items.prefix(s.n))
        }
        if s.mode == "adapt", let A = s.adapt, !A.hist.isEmpty {
            let h = A.hist.suffix(8) + [A.lvl]
            let est = Double(h.reduce(0, +)) / Double(h.count)
            s.est = est
            db.est.adapt = est
        }
        s.done = (Date().timeIntervalSince1970 * 1000).rounded()
        db.current = nil
        if s.n > 0 {
            db.sessions.append(s)
            if db.sessions.count > 300 { db.sessions = Array(db.sessions.suffix(300)) }
        }
        save()
        recomputeSummary()
        return s.n > 0 ? s.id : nil
    }

    // MARK: Backup

    /// Backup com os dois modos: Psicotécnico (formato de sempre) e Palográfico.
    func backupData(palo: PaloStore) -> Data? {
        let b = PsicoBackup(settings: db.settings, sessions: db.sessions, est: db.est, palografico: .current(palo))
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return try? enc.encode(b)
    }

    func parseBackup(_ data: Data) -> PsicoBackup? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["sessions"] is [Any] else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(PsicoBackup.self, from: data)
    }

    func restore(_ b: PsicoBackup) {
        db.sessions = b.sessions
        db.est = b.est ?? PsicoEst()
        db.settings = b.settings ?? PsicoSettings()
        save()
        recomputeSummary()
    }

    func clearHistory() {
        db.sessions = []
        db.est = PsicoEst()
        db.current = nil
        save()
        recomputeSummary()
    }
}
