import Foundation
import SwiftUI

/// Os três modos do Palográfico.
enum PaloMode: String, Codable, CaseIterable, Identifiable {
    case treino, teste, livre

    var id: String { rawValue }

    var title: String {
        switch self {
        case .treino: return "Treino"
        case .teste: return "Teste"
        case .livre: return "Livre"
        }
    }

    /// Número de ciclos de 60 s. nil = sem limite (Livre).
    var cycles: Int? {
        switch self {
        case .treino: return 3
        case .teste: return 5
        case .livre: return nil
        }
    }

    /// No Teste nada pode mostrar o tempo.
    var showsTimer: Bool { self != .teste }

    var summary: String {
        switch self {
        case .treino: return "3 ciclos de 60 s, com cronômetro visível."
        case .teste: return "5 ciclos de 60 s. A tela mostra só o ciclo, sem tempo. Não tem pausa: abortar descarta a sessão."
        case .livre: return "Ciclos de 60 s até você encerrar, com cronômetro visível. Não entra na média nem no histórico de desempenho."
        }
    }
}

enum PaloConstants {
    /// Ciclos fixos de 60 s, sem variação.
    static let cycleSeconds: TimeInterval = 60
    /// Contagem regressiva antes de começar.
    static let countdownSeconds = 3
    /// Validação de cada contagem.
    static let countRange = 0...400
}

/// Uma sessão salva no histórico.
struct PaloRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var mode: PaloMode
    var counts: [Int]
    var soundOn: Bool
    var vibrationOn: Bool
    var note: String
    /// Maior desvio medido entre o bip agendado e o disparado (ms). Diagnóstico.
    var maxBeepDeviationMs: Double?

    var metrics: PaloMetrics { PaloMetrics(counts: counts) }
}

struct PaloMetrics {
    let counts: [Int]

    var total: Int { counts.reduce(0, +) }
    var mean: Double { counts.isEmpty ? 0 : Double(total) / Double(counts.count) }
    /// Soma das diferenças absolutas entre ciclos consecutivos.
    var oscillation: Int {
        guard counts.count > 1 else { return 0 }
        return zip(counts, counts.dropFirst()).reduce(0) { $0 + abs($1.1 - $1.0) }
    }

    /// Índices (0-based) dos valores que destoam muito dos demais.
    /// Compara cada valor com a mediana dos outros; só um aviso, não bloqueia.
    static func outliers(_ values: [Int]) -> [Int] {
        guard values.count >= 3 else { return [] }
        var result: [Int] = []
        for (i, v) in values.enumerated() {
            var others = values
            others.remove(at: i)
            let med = median(others)
            let tolerance = max(25.0, med * 0.35)
            if abs(Double(v) - med) > tolerance { result.append(i) }
        }
        return result
    }

    static func median(_ values: [Int]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        if s.count % 2 == 1 { return Double(s[s.count / 2]) }
        return Double(s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}

/// Faixas de referência (editáveis). Aplicadas ao total dos 5 ciclos do Teste.
/// Rótulo fixo: "referência não oficial".
struct PaloBands {
    var mediaMin: Int      // 547
    var altaMin: Int       // 831
    var superiorMin: Int   // 1060

    static let defaults = PaloBands(mediaMin: 547, altaMin: 831, superiorMin: 1060)

    var isValid: Bool { mediaMin < altaMin && altaMin < superiorMin && mediaMin >= 0 }

    struct Band: Equatable {
        let label: String
        let range: String
    }

    var all: [Band] {
        [
            Band(label: "Média", range: "\(mediaMin)–\(altaMin - 1)"),
            Band(label: "Média superior ou alta", range: "\(altaMin)–\(superiorMin - 1)"),
            Band(label: "Superior ou muito alta", range: "\(superiorMin) ou mais"),
        ]
    }

    func classify(total: Int) -> Band {
        if total >= superiorMin { return all[2] }
        if total >= altaMin { return all[1] }
        if total >= mediaMin { return all[0] }
        return Band(label: "Abaixo das faixas listadas", range: "menos de \(mediaMin)")
    }
}

/// Chaves de UserDefaults.
enum PaloKeys {
    static let sound = "palo.sound"
    static let vibration = "palo.vibration"
    static let notificationFallback = "palo.notificationFallback"
    static let mode = "palo.mode"
    static let bandMedia = "palo.band.media"
    static let bandAlta = "palo.band.alta"
    static let bandSuperior = "palo.band.superior"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            sound: true,
            vibration: true,
            notificationFallback: false,
            mode: PaloMode.treino.rawValue,
            bandMedia: PaloBands.defaults.mediaMin,
            bandAlta: PaloBands.defaults.altaMin,
            bandSuperior: PaloBands.defaults.superiorMin,
        ])
    }

    static var bands: PaloBands {
        let d = UserDefaults.standard
        let b = PaloBands(mediaMin: d.integer(forKey: bandMedia),
                          altaMin: d.integer(forKey: bandAlta),
                          superiorMin: d.integer(forKey: bandSuperior))
        return b.isValid ? b : .defaults
    }
}

/// Histórico em arquivo JSON em Application Support.
final class PaloStore: ObservableObject {
    @Published private(set) var records: [PaloRecord] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("palografico-historico.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = (try? decoder.decode([PaloRecord].self, from: data)) ?? []
        }
    }

    func records(for mode: PaloMode) -> [PaloRecord] {
        records.filter { $0.mode == mode }.sorted { $0.date > $1.date }
    }

    func add(_ record: PaloRecord) {
        records.append(record)
        persist()
    }

    func delete(_ id: UUID) {
        records.removeAll { $0.id == id }
        persist()
    }

    func updateNote(_ id: UUID, note: String) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].note = note
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        let url = self.url
        DispatchQueue.global(qos: .utility).async {
            try? data.write(to: url, options: .atomic)
        }
    }
}
