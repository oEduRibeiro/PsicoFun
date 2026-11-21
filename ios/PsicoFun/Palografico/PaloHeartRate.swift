import CoreBluetooth
import Foundation
import UIKit

// MARK: - Dados salvos

/// FC de uma sessão, resumida por ciclo. Fica no histórico como campo opcional:
/// sessões antigas (ou com o recurso desligado) simplesmente não têm este campo.
///
/// Ausência de leitura é sempre `nil`, nunca zero, para não puxar médias para baixo.
struct PaloHeartRate: Codable, Equatable {
    /// Nome do relógio/sensor, se conhecido.
    var deviceName: String?
    /// Um item por ciclo completo, na ordem.
    var cycles: [PaloHRCycle]

    /// Pelo menos um ciclo teve leitura.
    var hasData: Bool { cycles.contains { $0.mean != nil } }

    /// Média da sessão, ponderada pela quantidade de leituras de cada ciclo.
    var mean: Double? {
        let withData = cycles.filter { $0.mean != nil && $0.samples > 0 }
        let n = withData.reduce(0) { $0 + $1.samples }
        guard n > 0 else { return nil }
        return withData.reduce(0.0) { $0 + ($1.mean ?? 0) * Double($1.samples) } / Double(n)
    }

    var min: Int? { cycles.compactMap { $0.min }.min() }
    var max: Int? { cycles.compactMap { $0.max }.max() }

    /// Fração média dos segundos com leitura, de 0 a 1.
    var coverage: Double {
        guard !cycles.isEmpty else { return 0 }
        return cycles.reduce(0) { $0 + $1.coverage } / Double(cycles.count)
    }

    var isPartial: Bool { cycles.contains { $0.isPartial } }
}

struct PaloHRCycle: Codable, Equatable {
    var mean: Double?
    var min: Int?
    var max: Int?
    /// Fração dos 60 segundos do ciclo que tiveram pelo menos uma leitura (0 a 1).
    var coverage: Double
    /// Quantidade de leituras válidas no ciclo.
    var samples: Int

    /// Abaixo disso o ciclo aparece como "parcial".
    static let partialThreshold = 0.6

    var isPartial: Bool { mean != nil && coverage < Self.partialThreshold }
}

struct PaloHRSample: Equatable {
    let date: Date
    let bpm: Int
}

extension PaloHeartRate {
    /// Resume as leituras em ciclos de 60 s a partir de `start`.
    static func summarize(samples: [PaloHRSample], start: Date, cycles: Int, deviceName: String?) -> PaloHeartRate {
        let length = PaloConstants.cycleSeconds
        let items: [PaloHRCycle] = (0..<Swift.max(0, cycles)).map { k in
            let from = start.addingTimeInterval(TimeInterval(k) * length)
            let to = from.addingTimeInterval(length)
            let inCycle = samples.filter { $0.date >= from && $0.date < to }
            guard !inCycle.isEmpty else {
                return PaloHRCycle(mean: nil, min: nil, max: nil, coverage: 0, samples: 0)
            }
            let seconds = Set(inCycle.map { Int($0.date.timeIntervalSince(from)) })
            let values = inCycle.map { $0.bpm }
            return PaloHRCycle(mean: Double(values.reduce(0, +)) / Double(values.count),
                               min: values.min(),
                               max: values.max(),
                               coverage: Swift.min(1, Double(seconds.count) / length),
                               samples: values.count)
        }
        return PaloHeartRate(deviceName: deviceName, cycles: items)
    }
}

// MARK: - Leitor Bluetooth (perfil Heart Rate 0x180D)

/// Lê a frequência cardíaca de um relógio ou cinta que transmite pelo perfil
/// Bluetooth padrão de FC (no relógio: "transmitir FC" / "broadcast HR").
///
/// - Só cria o `CBCentralManager` (e só pede permissão) quando o recurso é ligado.
/// - Lembra o último aparelho e reconecta sozinho se a conexão cair.
/// - Fora de uma sessão, solta a conexão quando o app vai para segundo plano,
///   para não gastar bateria do relógio à toa. Durante a sessão mantém
///   (modo de segundo plano "bluetooth-central").
/// - Nunca bloqueia a sessão nem mostra alerta: se não houver leitura, não há dado.
///
/// Todos os callbacks rodam na main thread.
final class PaloHeartRateMonitor: NSObject, ObservableObject {
    static let shared = PaloHeartRateMonitor()

    enum Status: Equatable {
        case off
        case unauthorized
        case bluetoothOff
        case unsupported
        case searching
        case connecting(String)
        case connected(String)
    }

    @Published private(set) var status: Status = .off
    /// Última leitura válida (para o status na preparação). Some após alguns segundos sem leitura.
    @Published private(set) var latestBPM: Int?
    @Published private(set) var rememberedName: String?

    private static let heartRateService = CBUUID(string: "180D")
    private static let measurementChar = CBUUID(string: "2A37")
    private static let validRange = 30...230
    private static let staleAfter: TimeInterval = 5

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var wanted = false
    private var keepInBackground = false
    private var inBackground = false
    private var recording: [PaloHRSample]?
    private var staleTimer: Timer?

    private override init() {
        super.init()
        rememberedName = UserDefaults.standard.string(forKey: PaloKeys.hrDeviceName)
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(didEnterBackground),
                       name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(willEnterForeground),
                       name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    /// Permissão do Bluetooth recusada nos Ajustes.
    static var isDenied: Bool {
        let a = CBCentralManager.authorization
        return a == .denied || a == .restricted
    }

    var connectedName: String? {
        if case .connected(let name) = status { return name }
        return nil
    }

    // MARK: Comandos

    /// Liga o leitor (procura/conecta). Chamado quando o interruptor está ligado.
    func activate() {
        wanted = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
            // O estado chega em centralManagerDidUpdateState.
        } else {
            connectIfPossible()
        }
    }

    /// Desliga o leitor e solta a conexão.
    func deactivate() {
        wanted = false
        keepInBackground = false
        disconnect()
        status = .off
    }

    /// Esquece o aparelho lembrado e procura de novo.
    func forgetDevice() {
        UserDefaults.standard.removeObject(forKey: PaloKeys.hrDeviceID)
        UserDefaults.standard.removeObject(forKey: PaloKeys.hrDeviceName)
        rememberedName = nil
        disconnect()
        if wanted { connectIfPossible() }
    }

    /// Começa a guardar leituras (início da sessão). Mantém a conexão em segundo plano.
    func beginRecording() {
        recording = []
        keepInBackground = true
        activate()
    }

    /// Para de guardar e devolve as leituras. Fora da sessão, solta a conexão se o app estiver em segundo plano.
    @discardableResult
    func endRecording() -> [PaloHRSample] {
        let samples = recording ?? []
        recording = nil
        keepInBackground = false
        if inBackground { disconnect() }
        return samples
    }

    // MARK: Conexão

    private func connectIfPossible() {
        guard wanted, let central = central else { return }
        switch central.state {
        case .poweredOn:
            break
        case .unauthorized:
            status = .unauthorized; return
        case .unsupported:
            status = .unsupported; return
        case .poweredOff:
            status = .bluetoothOff; return
        default:
            return // .unknown / .resetting: espera o próximo estado
        }
        if inBackground && !keepInBackground { return }
        if let p = peripheral, p.state == .connected || p.state == .connecting { return }

        // 1) Aparelho lembrado.
        if let idString = UserDefaults.standard.string(forKey: PaloKeys.hrDeviceID),
           let id = UUID(uuidString: idString),
           let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(p)
            return
        }
        // 2) Algum aparelho com o serviço de FC já conectado ao iPhone por outro app.
        if let p = central.retrieveConnectedPeripherals(withServices: [Self.heartRateService]).first {
            connect(p)
            return
        }
        // 3) Procurar.
        status = .searching
        central.scanForPeripherals(withServices: [Self.heartRateService], options: nil)
    }

    private func connect(_ p: CBPeripheral) {
        central?.stopScan()
        peripheral = p
        p.delegate = self
        status = .connecting(displayName(p))
        // Sem tempo limite: se o relógio sumir, a conexão fica pendente e completa quando ele voltar.
        central?.connect(p, options: nil)
    }

    private func disconnect() {
        central?.stopScan()
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        setLatest(nil)
        if wanted { status = .searching }
    }

    private func displayName(_ p: CBPeripheral) -> String {
        p.name ?? rememberedName ?? "Relógio"
    }

    private func setLatest(_ bpm: Int?) {
        latestBPM = bpm
        staleTimer?.invalidate()
        guard bpm != nil else { return }
        staleTimer = Timer.scheduledTimer(withTimeInterval: Self.staleAfter, repeats: false) { [weak self] _ in
            self?.latestBPM = nil
        }
    }

    @objc private func didEnterBackground() {
        inBackground = true
        if !keepInBackground && peripheral != nil { disconnect() }
    }

    @objc private func willEnterForeground() {
        inBackground = false
        if wanted { connectIfPossible() }
    }

    // MARK: Leitura

    /// Interpreta a característica Heart Rate Measurement (0x2A37).
    /// Devolve nil se o relógio indicar que perdeu o contato com a pele ou se o valor for impossível.
    static func parseMeasurement(_ data: Data) -> Int? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }
        let flags = bytes[0]
        let is16Bit = flags & 0x01 != 0
        let contactSupported = flags & 0x04 != 0
        let contactDetected = flags & 0x02 != 0
        if contactSupported && !contactDetected { return nil }
        let bpm: Int
        if is16Bit {
            guard bytes.count >= 3 else { return nil }
            bpm = Int(bytes[1]) | (Int(bytes[2]) << 8)
        } else {
            bpm = Int(bytes[1])
        }
        return validRange.contains(bpm) ? bpm : nil
    }

    private func receive(_ bpm: Int) {
        setLatest(bpm)
        recording?.append(PaloHRSample(date: Date(), bpm: bpm))
    }
}

extension PaloHeartRateMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            connectIfPossible()
        } else {
            peripheral = nil
            setLatest(nil)
            switch central.state {
            case .unauthorized: status = .unauthorized
            case .unsupported: status = .unsupported
            case .poweredOff: status = .bluetoothOff
            default: break
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard wanted, self.peripheral == nil else { return }
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral == self.peripheral else { return }
        let name = displayName(peripheral)
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: PaloKeys.hrDeviceID)
        UserDefaults.standard.set(name, forKey: PaloKeys.hrDeviceName)
        rememberedName = name
        status = .connected(name)
        peripheral.discoverServices([Self.heartRateService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral == self.peripheral else { return }
        self.peripheral = nil
        status = .searching
        // Tenta de novo um pouco depois, sem insistir em loop apertado.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.connectIfPossible() }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == self.peripheral else { return }
        setLatest(nil)
        guard wanted, !(inBackground && !keepInBackground) else {
            self.peripheral = nil
            return
        }
        // Reconecta sozinho (fica pendente até o relógio voltar).
        status = .connecting(displayName(peripheral))
        central.connect(peripheral, options: nil)
    }
}

extension PaloHeartRateMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.heartRateService }) else { return }
        peripheral.discoverCharacteristics([Self.measurementChar], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let c = service.characteristics?.first(where: { $0.uuid == Self.measurementChar }) else { return }
        peripheral.setNotifyValue(true, for: c)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == Self.measurementChar,
              let data = characteristic.value, let bpm = Self.parseMeasurement(data) else { return }
        receive(bpm)
    }
}
