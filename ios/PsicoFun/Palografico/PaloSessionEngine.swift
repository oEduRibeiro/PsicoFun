import ActivityKit
import Foundation
import UIKit
import UserNotifications

/// Motor da sessão do Palográfico: contagem de 3 s, bips a cada 60 s, sinais
/// (visual / som / vibração), Live Activity e notificações de reserva.
///
/// Precisão: todos os instantes saem de um `startDate` único
/// (bip k = startDate + k × 60 s). Cada evento é agendado de novo a partir desse
/// instante absoluto, então o erro não acumula entre ciclos. O timer roda numa
/// fila própria (não depende da main thread nem da tela), e o som e a vibração
/// disparam direto nessa fila.
///
/// Todas as propriedades `@Published` só mudam na main thread.
final class PaloSessionEngine: ObservableObject {
    enum Stage: Equatable {
        /// Tela de preparação.
        case idle
        /// Contagem antes de começar (3, 2, 1).
        case countdown(Int)
        /// Sessão em andamento.
        case running
        /// Sessão terminada, esperando as contagens.
        case entry
        /// Contagens salvas, mostrando o resultado.
        case results(PaloRecord)
    }

    /// Ajustes travados no início da sessão.
    struct Config: Equatable {
        var sound: Bool
        var vibration: Bool
        var notificationFallback: Bool
        /// Gravar FC do relógio (opcional; a sessão nunca depende disso).
        var heartRate: Bool = false
    }

    @Published private(set) var stage: Stage = .idle
    /// true durante contagem e sessão (esconde o seletor do topo e a barra de status).
    @Published private(set) var isRunning = false
    @Published private(set) var mode: PaloMode = .treino
    @Published private(set) var config = Config(sound: true, vibration: true, notificationFallback: false)
    @Published private(set) var currentCycle = 1
    /// Ciclos completos ao terminar (5 no Teste, 3 no Treino, variável no Livre).
    @Published private(set) var completedCycles = 0
    /// Incrementa a cada sinal; a tela usa para disparar o pulso visual.
    @Published private(set) var pulse = 0
    @Published private(set) var startDate = Date()
    /// Desvios medidos (ms) entre o instante agendado e o disparo de cada bip.
    @Published private(set) var deviationsMs: [Double] = []
    /// FC resumida por ciclo, calculada ao terminar (nil se o recurso estava desligado).
    private var pendingHeartRate: PaloHeartRate?

    var totalCycles: Int { mode.cycles ?? 0 }

    private let audio = PaloAudio()
    private let liveActivity = PaloLiveActivityController()
    private let notifier = PaloNotifier.shared
    private let heartRate = PaloHeartRateMonitor.shared

    // Estado da fila do timer (só acessado em `queue`).
    private let queue = DispatchQueue(label: "psicofun.palografico.timer", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var queueToken = UUID()
    private var queueConfig = Config(sound: true, vibration: true, notificationFallback: false)
    private var queueTotal = 0
    private var queueStart = Date()

    // Token da sessão na main thread, para ignorar eventos atrasados de uma sessão abortada.
    private var mainToken = UUID()

    init() {
        PaloLiveActivityController.endStaleActivities()
    }

    // MARK: - Comandos (main thread)

    func start(mode: PaloMode, config: Config) {
        guard stage == .idle else { return }
        let token = UUID()
        let anchor = Date()
        let start = anchor.addingTimeInterval(TimeInterval(PaloConstants.countdownSeconds))

        mainToken = token
        self.mode = mode
        self.config = config
        currentCycle = 1
        completedCycles = 0
        deviationsMs = []
        pendingHeartRate = nil
        startDate = start
        stage = .countdown(PaloConstants.countdownSeconds)
        isRunning = true

        UIApplication.shared.isIdleTimerDisabled = true
        audio.activate()
        // A Live Activity precisa ser pedida com o app em primeiro plano: pedimos já na contagem.
        liveActivity.start(state: activityState(cycle: 1, finished: false))
        // Só grava: nada de FC aparece na tela durante a sessão.
        if config.heartRate { heartRate.beginRecording() }
        if config.notificationFallback {
            notifier.schedule(mode: mode, start: start, total: mode.cycles)
        }

        let total = mode.cycles ?? 0
        queue.async { [self] in
            queueToken = token
            queueConfig = config
            queueTotal = total
            queueStart = start
            arm(event: -(PaloConstants.countdownSeconds - 1), token: token)
        }
    }

    /// Abortar: descarta a sessão e encerra a Live Activity.
    func abort() {
        guard isRunning else { return }
        stopHardware()
        liveActivity.end(finalState: nil)
        stage = .idle
    }

    /// Livre: encerra e vai para a entrada das contagens dos ciclos completos.
    func finishLivre() {
        guard isRunning, mode == .livre else { return }
        let done: Int
        if case .running = stage { done = max(0, currentCycle - 1) } else { done = 0 }
        captureHeartRate(cycles: done)
        stopHardware()
        liveActivity.end(finalState: nil)
        completedCycles = done
        stage = .entry
    }

    func save(counts: [Int], note: String, into store: PaloStore) {
        guard case .entry = stage else { return }
        let record = PaloRecord(date: startDate, mode: mode, counts: counts,
                                soundOn: config.sound, vibrationOn: config.vibration,
                                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                maxBeepDeviationMs: deviationsMs.map { abs($0) }.max(),
                                heartRate: pendingHeartRate)
        store.add(record)
        stage = .results(record)
    }

    func discardEntry() {
        guard case .entry = stage else { return }
        pendingHeartRate = nil
        stage = .idle
    }

    func closeResults() {
        stage = .idle
    }

    // MARK: - Timer (fila própria)

    /// Evento < 0: contagem (−2 mostra "2", −1 mostra "1"); 0: início; k ≥ 1: bip k.
    private func eventDate(_ event: Int) -> Date {
        event < 0
            ? queueStart.addingTimeInterval(TimeInterval(event))
            : queueStart.addingTimeInterval(TimeInterval(event) * PaloConstants.cycleSeconds)
    }

    private func arm(event: Int, token: UUID) {
        let fire = eventDate(event)
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(wallDeadline: DispatchWallTime(date: fire), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in
            self?.fire(event: event, scheduled: fire, token: token)
        }
        timer?.cancel()
        timer = t
        t.resume()
    }

    private func fire(event: Int, scheduled: Date, token: UUID) {
        guard token == queueToken else { return }
        let deviation = Date().timeIntervalSince(scheduled) * 1000
        let cfg = queueConfig

        if event >= 0 {
            if cfg.sound { audio.play(event == 0 ? .start : .signal) }
            if cfg.vibration { PaloAudio.vibrate() }
        }

        let isLast = queueTotal > 0 && event >= queueTotal
        if isLast {
            timer?.cancel()
            timer = nil
        } else {
            arm(event: event + 1, token: token)
        }

        DispatchQueue.main.async { [weak self] in
            self?.apply(event: event, deviationMs: deviation, isLast: isLast, token: token)
        }
    }

    // MARK: - Estado (main thread)

    private func apply(event: Int, deviationMs: Double, isLast: Bool, token: UUID) {
        guard token == mainToken, isRunning else { return }
        if event < 0 {
            stage = .countdown(-event)
            return
        }
        pulse += 1
        if event == 0 {
            stage = .running
            liveActivity.update(state: activityState(cycle: 1, finished: false))
            return
        }
        deviationsMs.append(deviationMs)
        if isLast {
            completedCycles = totalCycles
            captureHeartRate(cycles: totalCycles)
            stopHardware()
            liveActivity.end(finalState: activityState(cycle: totalCycles, finished: true))
            stage = .entry
        } else {
            currentCycle = event + 1
            // No Teste, isto é o que avança a Live Activity (sem tempo nenhum na tela).
            liveActivity.update(state: activityState(cycle: currentCycle, finished: false))
        }
    }

    private func stopHardware() {
        mainToken = UUID()
        queue.sync {
            queueToken = UUID()
            timer?.cancel()
            timer = nil
        }
        isRunning = false
        // Abortar descarta as leituras; ao terminar, captureHeartRate já as pegou.
        if config.heartRate { heartRate.endRecording() }
        UIApplication.shared.isIdleTimerDisabled = false
        notifier.cancel()
        // Deixa o último bip terminar de tocar antes de soltar a sessão de áudio.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, !self.isRunning else { return }
            self.audio.deactivate()
        }
    }

    /// Resume a FC gravada nos ciclos completos. Sem leitura nenhuma, guarda os ciclos vazios
    /// (o resultado mostra "sem dados"), nunca zeros.
    private func captureHeartRate(cycles: Int) {
        guard config.heartRate else { pendingHeartRate = nil; return }
        let samples = heartRate.endRecording()
        pendingHeartRate = cycles > 0
            ? PaloHeartRate.summarize(samples: samples, start: startDate, cycles: cycles,
                                      deviceName: heartRate.connectedName ?? heartRate.rememberedName)
            : nil
    }

    private func activityState(cycle: Int, finished: Bool) -> PaloActivityAttributes.ContentState {
        let interval: ClosedRange<Date>?
        switch mode {
        case .teste:
            interval = nil // nunca revelar tempo no Teste
        case .treino:
            interval = startDate...startDate.addingTimeInterval(TimeInterval(totalCycles) * PaloConstants.cycleSeconds)
        case .livre:
            interval = startDate...startDate.addingTimeInterval(12 * 3600)
        }
        return PaloActivityAttributes.ContentState(
            phase: mode.rawValue,
            phaseTitle: mode.title,
            currentCycle: cycle,
            totalCycles: totalCycles,
            phaseInterval: finished ? nil : interval,
            finished: finished)
    }
}

extension DispatchWallTime {
    init(date: Date) {
        let t = date.timeIntervalSince1970
        let sec = floor(t)
        let nsec = (t - sec) * 1_000_000_000
        self.init(timespec: timespec(tv_sec: Int(sec), tv_nsec: Int(nsec)))
    }
}

// MARK: - Live Activity

/// Encapsula o ActivityKit. Se Live Activities estiverem desativadas ou falharem,
/// tudo aqui vira no-op e a sessão segue normalmente.
final class PaloLiveActivityController {
    private var activity: Activity<PaloActivityAttributes>?

    func start(state: PaloActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            if #available(iOS 16.2, *) {
                activity = try Activity.request(attributes: PaloActivityAttributes(),
                                                content: ActivityContent(state: state, staleDate: nil),
                                                pushType: nil)
            } else {
                activity = try Activity.request(attributes: PaloActivityAttributes(),
                                                contentState: state, pushType: nil)
            }
        } catch {
            NSLog("Palográfico: Live Activity indisponível: \(error)")
            activity = nil
        }
    }

    func update(state: PaloActivityAttributes.ContentState) {
        guard let activity = activity else { return }
        Task {
            if #available(iOS 16.2, *) {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            } else {
                await activity.update(using: state)
            }
        }
    }

    /// Com estado final: mostra "Sessão encerrada" por alguns segundos. Sem: some na hora (abortar).
    func end(finalState: PaloActivityAttributes.ContentState?) {
        guard let activity = activity else { return }
        self.activity = nil
        Task {
            let policy: ActivityUIDismissalPolicy = finalState == nil
                ? .immediate
                : .after(Date().addingTimeInterval(30))
            if #available(iOS 16.2, *) {
                let content = finalState.map { ActivityContent(state: $0, staleDate: nil) }
                await activity.end(content, dismissalPolicy: policy)
            } else {
                await activity.end(using: finalState, dismissalPolicy: policy)
            }
        }
    }

    /// Se o app foi encerrado no meio de uma sessão, a atividade antiga ficaria presa.
    static func endStaleActivities() {
        Task {
            for activity in Activity<PaloActivityAttributes>.activities {
                if #available(iOS 16.2, *) {
                    await activity.end(nil, dismissalPolicy: .immediate)
                } else {
                    await activity.end(using: nil, dismissalPolicy: .immediate)
                }
            }
        }
    }
}

// MARK: - Notificações de reserva

/// Reserva opcional (desligada por padrão): uma notificação local por bip, para o
/// caso de a vibração em segundo plano não ser confiável no aparelho.
/// Com o app em primeiro plano elas não aparecem (o sinal já é dado pelo app).
final class PaloNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PaloNotifier()
    private static let prefix = "palo.beep."

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Agenda uma notificação para cada bip. Livre: as próximas 60 (limite do iOS é 64).
    func schedule(mode: PaloMode, start: Date, total: Int?) {
        cancel()
        let center = UNUserNotificationCenter.current()
        let count = total ?? 60
        for k in 1...count {
            let fire = start.addingTimeInterval(TimeInterval(k) * PaloConstants.cycleSeconds)
            let interval = fire.timeIntervalSinceNow
            guard interval > 0 else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Palográfico · \(mode.title)"
            if let total = total {
                content.body = k == total ? "Sinal final. Pare e conte." : "Sinal. Ciclo \(k + 1) de \(total)."
            } else {
                content.body = "Sinal. Ciclo \(k + 1)."
            }
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: Self.prefix + "\(k)", content: content, trigger: trigger))
        }
    }

    func cancel() {
        let ids = (1...64).map { Self.prefix + "\($0)" }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }
}
