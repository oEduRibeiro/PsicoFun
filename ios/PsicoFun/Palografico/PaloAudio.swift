import AVFoundation
import AudioToolbox

/// Áudio do Palográfico.
///
/// - Sessão `.playback` + background mode `audio` (Info.plist), para o app continuar
///   vivo com a tela bloqueada: é isso que mantém o timer dos bips, a vibração e as
///   atualizações da Live Activity funcionando em segundo plano.
/// - Um buffer mudo toca em loop durante toda a sessão, com o som ligado ou não.
///   Sem ele, com o som desligado, o iOS suspenderia o app.
/// - Os sons (início e sinal) são gerados na hora, sem arquivos de áudio.
final class PaloAudio {
    enum Cue { case start, signal }

    private let engine = AVAudioEngine()
    private let silentNode = AVAudioPlayerNode()
    private let cueNode = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let silentBuffer: AVAudioPCMBuffer
    /// Som de início: duas notas subindo.
    private let startBuffer: AVAudioPCMBuffer
    /// Som do sinal: um bip único, diferente do início.
    private let signalBuffer: AVAudioPCMBuffer
    private var observers: [NSObjectProtocol] = []
    private(set) var isActive = false

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        self.format = format
        silentBuffer = Self.makeSilence(format: format, seconds: 1)
        startBuffer = Self.makeTones(format: format, notes: [(660, 0.12), (0, 0.04), (990, 0.18)])
        signalBuffer = Self.makeTones(format: format, notes: [(1_000, 0.22)])
        engine.attach(silentNode)
        engine.attach(cueNode)
        engine.connect(silentNode, to: engine.mainMixerNode, format: format)
        engine.connect(cueNode, to: engine.mainMixerNode, format: format)
    }

    deinit {
        removeObservers()
    }

    /// Ativa a sessão de áudio e começa o loop mudo.
    func activate() {
        guard !isActive else { return }
        isActive = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            NSLog("PaloAudio: falha ao ativar a sessão: \(error)")
        }
        startEngine()
        observe()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        removeObservers()
        cueNode.stop()
        silentNode.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Toca um som. Seguro para chamar de qualquer thread.
    func play(_ cue: Cue) {
        guard isActive else { return }
        if !engine.isRunning { startEngine() }
        let buffer = cue == .start ? startBuffer : signalBuffer
        cueNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !cueNode.isPlaying { cueNode.play() }
    }

    /// Vibração que funciona também em segundo plano / tela bloqueada.
    /// (`UIImpactFeedbackGenerator` só funciona em primeiro plano.)
    static func vibrate() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    private func removeObservers() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
    }

    // MARK: - Engine

    private func startEngine() {
        do {
            engine.prepare()
            try engine.start()
            silentNode.stop()
            silentNode.scheduleBuffer(silentBuffer, at: nil, options: .loops, completionHandler: nil)
            silentNode.play()
            cueNode.play()
        } catch {
            NSLog("PaloAudio: falha ao iniciar o engine: \(error)")
        }
    }

    private func observe() {
        let nc = NotificationCenter.default
        // Ligação, Siri, alarme: ao terminar a interrupção, retoma o áudio (e o loop mudo).
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification,
                                        object: nil, queue: .main) { [weak self] note in
            guard let self = self, self.isActive,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .ended {
                try? AVAudioSession.sharedInstance().setActive(true)
                self.startEngine()
            }
        })
        // Troca de rota (fone conectado/desconectado) pode parar o engine.
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange,
                                        object: engine, queue: .main) { [weak self] _ in
            guard let self = self, self.isActive else { return }
            self.startEngine()
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.isActive else { return }
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try? AVAudioSession.sharedInstance().setActive(true)
            self.startEngine()
        })
    }

    // MARK: - Síntese

    private static func makeSilence(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        if let ch = buffer.floatChannelData?[0] {
            for i in 0..<Int(frames) { ch[i] = 0 }
        }
        return buffer
    }

    /// Sequência de notas (frequência em Hz, duração em s). Frequência 0 = pausa.
    private static func makeTones(format: AVAudioFormat, notes: [(Double, Double)]) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let total = notes.reduce(0) { $0 + Int(rate * $1.1) }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total))!
        buffer.frameLength = AVAudioFrameCount(total)
        guard let ch = buffer.floatChannelData?[0] else { return buffer }
        var offset = 0
        for (freq, dur) in notes {
            let n = Int(rate * dur)
            let fade = min(Int(rate * 0.008), n / 2) // 8 ms de rampa para não estalar
            for i in 0..<n {
                var amp: Double = freq > 0 ? 0.6 : 0
                if i < fade { amp *= Double(i) / Double(max(fade, 1)) }
                if i > n - fade { amp *= Double(n - i) / Double(max(fade, 1)) }
                ch[offset + i] = Float(amp * sin(2 * .pi * freq * Double(i) / rate))
            }
            offset += n
        }
        return buffer
    }
}
