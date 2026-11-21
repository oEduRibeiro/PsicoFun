import Foundation

// MARK: - Dados salvos (mesmo formato JSON do app web, "psicovisual.v1")
//
// O arquivo psicofun-state.json em Application Support já era a cópia principal
// quando a interface rodava no WebView. Mantemos exatamente o mesmo formato
// para que o progresso continue de onde parou, e o backup exportado seja
// compatível com versões antigas (e vice-versa).

struct PsicoSettings: Codable, Equatable {
    var feedback: String = "eye"      // eye | auto | off
    var showCorrect: Bool = false
    var timer: Bool = true
    var qTime: Int = 0                // segundos; 0 = sem limite
    var showLevel: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        feedback = (try? c.decodeIfPresent(String.self, forKey: .feedback)) ?? "eye"
        showCorrect = (try? c.decodeIfPresent(Bool.self, forKey: .showCorrect)) ?? false
        timer = (try? c.decodeIfPresent(Bool.self, forKey: .timer)) ?? true
        qTime = (try? c.decodeIfPresent(Int.self, forKey: .qTime)) ?? 0
        showLevel = (try? c.decodeIfPresent(Bool.self, forKey: .showLevel)) ?? true
    }
}

struct PsicoEst: Codable, Equatable {
    var adapt: Double?
}

struct PsicoConfig: Codable, Equatable {
    var mode: String
    var fams: [String]?
    var lvl: Int?
    var from: Int?
    var to: Int?
    var n: Int?
    var minutes: Int?
    var keys: [String]?
}

struct PsicoItemSpec: Codable, Equatable {
    var fam: String
    var lvl: Int
    var seed: Int
    var prefer: [String]?
}

struct PsicoAnswer: Codable, Equatable {
    var c: Int
    var ok: Bool
    var ms: Double
    var to: Bool?
    var fam: String
    var lvl: Int
    var keys: [String]?
    var err: [String]?
}

struct PsicoAdapt: Codable, Equatable {
    var lvl: Int
    var streak: Int
    var hist: [Int]
}

struct PsicoSession: Codable, Equatable, Identifiable {
    var id: String
    var mode: String
    var created: Double
    var cfg: PsicoConfig?
    var items: [PsicoItemSpec]
    var ans: [PsicoAnswer?]
    var idx: Int
    var fb: String
    var elapsed: Double
    var n: Int
    var adapt: PsicoAdapt?
    var limit: Double?
    var done: Double?
    var est: Double?

    /// Respostas efetivas (sem buracos).
    var answers: [PsicoAnswer] { ans.compactMap { $0 } }

    func answer(at i: Int) -> PsicoAnswer? { i < ans.count ? ans[i] : nil }

    mutating func setAnswer(_ a: PsicoAnswer?, at i: Int) {
        while ans.count <= i { ans.append(nil) }
        ans[i] = a
    }

    init(id: String, mode: String, created: Double, cfg: PsicoConfig?, items: [PsicoItemSpec],
         idx: Int, fb: String, n: Int) {
        self.id = id; self.mode = mode; self.created = created; self.cfg = cfg; self.items = items
        self.ans = []; self.idx = idx; self.fb = fb; self.elapsed = 0; self.n = n
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        mode = (try? c.decode(String.self, forKey: .mode)) ?? "livre"
        created = (try? c.decode(Double.self, forKey: .created)) ?? 0
        cfg = try? c.decodeIfPresent(PsicoConfig.self, forKey: .cfg)
        items = (try? c.decode([PsicoItemSpec].self, forKey: .items)) ?? []
        ans = (try? c.decode([PsicoAnswer?].self, forKey: .ans)) ?? []
        idx = (try? c.decode(Int.self, forKey: .idx)) ?? 0
        fb = (try? c.decode(String.self, forKey: .fb)) ?? "eye"
        elapsed = (try? c.decode(Double.self, forKey: .elapsed)) ?? 0
        n = (try? c.decode(Int.self, forKey: .n)) ?? items.count
        adapt = try? c.decodeIfPresent(PsicoAdapt.self, forKey: .adapt)
        limit = try? c.decodeIfPresent(Double.self, forKey: .limit)
        done = try? c.decodeIfPresent(Double.self, forKey: .done)
        est = try? c.decodeIfPresent(Double.self, forKey: .est)
    }
}

struct PsicoDB: Codable, Equatable {
    var v: Int = 1
    var settings = PsicoSettings()
    var sessions: [PsicoSession] = []
    var current: PsicoSession?
    var est = PsicoEst()
    var saved: Double?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = (try? c.decode(Int.self, forKey: .v)) ?? 0
        settings = (try? c.decodeIfPresent(PsicoSettings.self, forKey: .settings)) ?? PsicoSettings()
        sessions = (try? c.decodeIfPresent([PsicoSession].self, forKey: .sessions)) ?? []
        current = try? c.decodeIfPresent(PsicoSession.self, forKey: .current)
        est = (try? c.decodeIfPresent(PsicoEst.self, forKey: .est)) ?? PsicoEst()
        saved = try? c.decodeIfPresent(Double.self, forKey: .saved)
    }
}

/// Formato do arquivo de backup. Os campos v/settings/sessions/est são os mesmos do
/// app web (backups antigos continuam restaurando). "palografico" é opcional: quando
/// existe, traz o histórico e os ajustes do Palográfico.
struct PsicoBackup: Codable {
    var v: Int = 1
    var settings: PsicoSettings?
    var sessions: [PsicoSession]
    var est: PsicoEst?
    var palografico: PaloBackup?
}

/// Parte do backup com os dados do Palográfico. A FC de cada sessão vai junto no
/// próprio registro (campo opcional heartRate), então backups sem FC continuam válidos.
struct PaloBackup: Codable {
    var records: [PaloRecord]
    var sound: Bool?
    var vibration: Bool?
    var notificationFallback: Bool?
    /// Gravar FC do relógio. O relógio pareado não vai no backup (é do aparelho).
    var heartRate: Bool?
    var mode: String?
    var bandMedia: Int?
    var bandAlta: Int?
    var bandSuperior: Int?

    static func current(_ store: PaloStore) -> PaloBackup {
        let d = UserDefaults.standard
        return PaloBackup(records: store.records,
                          sound: d.bool(forKey: PaloKeys.sound),
                          vibration: d.bool(forKey: PaloKeys.vibration),
                          notificationFallback: d.bool(forKey: PaloKeys.notificationFallback),
                          heartRate: d.bool(forKey: PaloKeys.heartRate),
                          mode: d.string(forKey: PaloKeys.mode),
                          bandMedia: d.integer(forKey: PaloKeys.bandMedia),
                          bandAlta: d.integer(forKey: PaloKeys.bandAlta),
                          bandSuperior: d.integer(forKey: PaloKeys.bandSuperior))
    }

    func apply(to store: PaloStore) {
        store.replaceAll(records)
        let d = UserDefaults.standard
        if let v = sound { d.set(v, forKey: PaloKeys.sound) }
        if let v = vibration { d.set(v, forKey: PaloKeys.vibration) }
        if let v = notificationFallback { d.set(v, forKey: PaloKeys.notificationFallback) }
        if let v = heartRate { d.set(v, forKey: PaloKeys.heartRate) }
        if let v = mode, PaloMode(rawValue: v) != nil { d.set(v, forKey: PaloKeys.mode) }
        if let m = bandMedia, let a = bandAlta, let s = bandSuperior,
           PaloBands(mediaMin: m, altaMin: a, superiorMin: s).isValid {
            d.set(m, forKey: PaloKeys.bandMedia)
            d.set(a, forKey: PaloKeys.bandAlta)
            d.set(s, forKey: PaloKeys.bandSuperior)
        }
    }
}

// MARK: - Questão gerada pelo motor

struct PFPanel: Codable, Hashable {
    var shape: String
    var count: Int
    var size: Int
    var fill: Int
    var rot: Int
    var mark: Int
    var lines: Int
    var ghost: Int?
}

struct PFCell: Codable, Hashable {
    var x: Int
    var y: Int
    var m: Int?
}

/// Figura: painel de atributos, poliminó (espacial) ou figura da intrusa.
struct PFFig: Codable, Hashable {
    var k: String
    var p: PFPanel?
    var compact: Bool?
    var cs: [PFCell]?
    var t: String?
    var shape: String?
    var n: Int?
    var fill: Int?
    var rot: Int?
    var inner: String?
}

/// Elemento da "cadeia" de explicação: valor, operador, rótulo, quebra ou mini figura.
struct PFChainEl: Codable, Hashable {
    var o: String?
    var v: String?
    var lab: String?
    var gap: Int?
    var fig: PFFig?
    var cap: String?
    var ans: Bool?
}

struct PFDiag: Codable, Hashable {
    var lines: [String]
    var traps: [String]?
    var vis: [PFChainEl]?
}

struct PFOption: Codable, Hashable {
    var fig: PFFig
    var errs: [String]
    var why: String?
    var diag: PFDiag?
}

struct PFStep: Codable, Hashable {
    var h: String
    var t: String
    var ch: [PFChainEl]?
}

struct PFStim: Codable, Hashable {
    var type: String
    var figs: [PFFig]
}

struct PsicoItem: Codable, Hashable {
    var fam: String
    var prompt: String
    var stim: PFStim
    var options: [PFOption]
    var answer: Int
    var keys: [String]
    var lvl: Int
    var seed: Int
    var letters: [String]
    var method: String
    var steps: [PFStep]
}

// MARK: - Textos fixos

enum PsicoText {
    static let famKeys = ["seq", "mat", "ana", "esp", "int"]
    static let fams = ["seq": "Sequência", "mat": "Matriz 3×3", "ana": "Analogia", "esp": "Rotação e espelho", "int": "Figura intrusa"]
    static let short = ["seq": "Sequência", "mat": "Matriz", "ana": "Analogia", "esp": "Rotação", "int": "Intrusa"]

    struct Mode {
        let key: String
        let name: String
        let desc: String
        let fbEnd: Bool
        let sample: (String, Int, Int)
    }

    static let modes: [Mode] = [
        Mode(key: "livre", name: "Treino livre", desc: "Você escolhe os tipos, o nível e a quantidade.", fbEnd: false, sample: ("mat", 3, 11)),
        Mode(key: "rampa", name: "Rampa progressiva", desc: "Começa fácil e a dificuldade sobe até a última questão.", fbEnd: false, sample: ("seq", 4, 7)),
        Mode(key: "simulado", name: "Simulado", desc: "Cronômetro e gabarito só no final, como na prova.", fbEnd: true, sample: ("mat", 6, 5)),
        Mode(key: "adapt", name: "Adaptativo", desc: "Sobe de nível a cada 2 acertos seguidos e desce a cada erro. Estima o seu nível.", fbEnd: false, sample: ("ana", 5, 3)),
        Mode(key: "foco", name: "Ponto fraco", desc: "Questões montadas nas regras que você mais erra.", fbEnd: false, sample: ("esp", 5, 9)),
    ]

    static func mode(_ key: String) -> Mode { modes.first { $0.key == key } ?? modes[0] }

    static let fbText = ["eyeC": "Correta na hora, explicação no olho", "eye": "Resposta na hora, escondida no olho",
                         "auto": "Resposta na hora", "off": "Resposta só no final", "end": "Resposta só no final"]
}

enum PsicoFormat {
    static func pct(_ a: Int, _ b: Int) -> Int { b > 0 ? Int((100 * Double(a) / Double(b)).rounded()) : 0 }

    static func duration(_ ms: Double) -> String {
        let s = Int((ms / 1000).rounded())
        return s < 60 ? "\(s) s" : "\(s / 60) min \(String(format: "%02d", s % 60)) s"
    }

    static func clock(_ ms: Double) -> String {
        let s = max(0, Int((ms / 1000).rounded(.up)))
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    static func level(_ v: Double) -> String {
        String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "pt_BR"); f.dateFormat = "dd/MM/yyyy"; return f
    }()
    private static let shortFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "pt_BR"); f.dateFormat = "dd/MM, HH:mm"; return f
    }()

    static func date(_ ms: Double) -> String { dateFmt.string(from: Date(timeIntervalSince1970: ms / 1000)) }
    static func dateTime(_ ms: Double) -> String { shortFmt.string(from: Date(timeIntervalSince1970: ms / 1000)) }
}
