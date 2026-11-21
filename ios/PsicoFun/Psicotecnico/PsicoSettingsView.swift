import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PsicoSettingsView: View {
    @ObservedObject var store: PsicoStore
    @ObservedObject var paloStore: PaloStore

    @State private var importChoice = false
    @State private var fileImporter = false
    @State private var pendingBackup: PsicoBackup?
    @State private var confirmClear = false

    private let feedbackOptions: [(String, String, String)] = [
        ("eye", "Escondida no olho", "Depois de responder, aparece um olho; a resposta só aparece se você tocar."),
        ("auto", "Mostrar na hora", "Correta, regra e motivo do erro aparecem assim que você responde."),
        ("off", "Só no final", "Nada durante o treino; tudo fica na revisão do resultado."),
    ]

    var body: some View {
        let st = store.settings
        PFScreen {
            PFEyebrow("Resposta nos modos de treino")
            PFCard(spacing: PF.Space.s) {
                ForEach(feedbackOptions.indices, id: \.self) { i in
                    let opt = feedbackOptions[i]
                    if i > 0 { PFDivider() }
                    Button {
                        guard st.feedback != opt.0 else { return }
                        Haptics.play("selection")
                        withAnimation(PF.Motion.quick) { store.updateSettings { $0.feedback = opt.0 } }
                    } label: {
                        feedbackRow(opt, on: st.feedback == opt.0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(st.feedback == opt.0 ? [.isSelected, .isButton] : .isButton)
                }
                PFDivider()
                PFToggleRow(icon: "checkmark.circle", title: "Mostrar alternativa correta",
                            subtitle: "Pinta a certa e a errada ao confirmar, mesmo com a explicação escondida no olho.",
                            isOn: binding(\.showCorrect))
                    .disabled(st.feedback != "eye")
                    .opacity(st.feedback != "eye" ? 0.5 : 1)
                Text("Vale para Treino livre, Rampa, Adaptativo e Ponto fraco. O Simulado sempre mostra só no final.")
                    .pfText(.footnote).foregroundColor(PF.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PFEyebrow("Durante a questão")
            PFCard(spacing: PF.Space.s) {
                PFToggleRow(icon: "timer", title: "Mostrar cronômetro", isOn: binding(\.timer))
                PFDivider()
                PFToggleRow(icon: "speedometer", title: "Mostrar o nível da questão", isOn: binding(\.showLevel))
                PFDivider()
                VStack(alignment: .leading, spacing: PF.Space.s) {
                    HStack(spacing: PF.Space.m) {
                        PFIconBadge(icon: "hourglass", size: 30)
                        Text("Tempo limite por questão (treino)").pfText(.body).foregroundColor(PF.ink)
                    }
                    PFSegmented<Int>(options: qTimeOptions, selection: Binding(get: { st.qTime }, set: { v in
                        store.updateSettings { $0.qTime = v }
                    }), compact: true)
                }
                .padding(.vertical, PF.Space.xs)
            }

            PFEyebrow("Seus dados")
            PFCard(spacing: PF.Space.s) {
                Button { exportBackup() } label: {
                    PFRow(icon: "square.and.arrow.up", title: "Exportar backup", subtitle: "Arquivo .json com os dois modos", chevron: true)
                }
                .buttonStyle(.plain)
                PFDivider()
                Button { importChoice = true } label: {
                    PFRow(icon: "arrow.counterclockwise", title: "Restaurar backup", subtitle: "De um arquivo ou de texto copiado", chevron: true)
                }
                .buttonStyle(.plain)
                PFDivider()
                Button { confirmClear = true } label: {
                    PFRow(icon: "trash", tone: .bad, title: "Apagar histórico do Psicotécnico")
                }
                .buttonStyle(.plain)
                Text("Salvo neste aparelho · \(store.db.sessions.count) sessões guardadas. O backup leva os dois modos: histórico e ajustes do Psicotécnico e do Palográfico. Para levar tudo para outro aparelho, exporte aqui e restaure lá.")
                    .pfText(.footnote).foregroundColor(PF.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, PF.Space.xs)
            }

            PFCard {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Cada questão nasce de regras, não de desenho livre: o gerador sorteia atributos (forma, quantidade, tamanho, preenchimento, rotação, posição, linhas) e regras para eles (progressão, alternância, ciclo, distribuição de três, soma, subtração, união e diferença de linhas), no modelo das matrizes de Raven.")
                        Text("Antes de aparecer, um solucionador separado tenta todas as regras possíveis em cada atributo. Se mais de uma resposta for defensável, a questão é descartada. As alternativas erradas mudam um ou mais atributos de forma equilibrada, para que a correta não se destaque por “ser a mais parecida com as outras”. Cada alternativa errada guarda qual regra ela viola — é assim que o relatório sabe o que você mais erra.")
                        Text("A mesma semente gera sempre a mesma questão, por isso a revisão de sessões antigas mostra exatamente o que você viu.")
                    }
                    .pfText(.footnote)
                    .foregroundColor(PF.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, PF.Space.s)
                } label: {
                    HStack(spacing: PF.Space.m) {
                        PFIconBadge(icon: "questionmark", size: 30)
                        Text("Como as questões são feitas").pfText(.body).foregroundColor(PF.ink)
                    }
                }
                .tint(PF.ink)
            }
        }
        .tint(PF.acc)
        .navigationTitle("Ajustes")
        .confirmationDialog("Restaurar backup", isPresented: $importChoice, titleVisibility: .visible) {
            Button("Abrir arquivo .json") { fileImporter = true }
            Button("Colar texto copiado") { importFromClipboard() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Escolha de onde vem o backup exportado pelo PsicoFun.")
        }
        .fileImporter(isPresented: $fileImporter, allowedContentTypes: [.json, .plainText, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { stage(data) } else { store.showToast("Não foi possível abrir o arquivo.") }
        }
        .alert("Restaurar backup?", isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } })) {
            Button("Cancelar", role: .cancel) { pendingBackup = nil }
            Button("Restaurar") {
                if let b = pendingBackup {
                    store.restore(b)
                    b.palografico?.apply(to: paloStore)
                }
                pendingBackup = nil
                Haptics.play("success")
                store.showToast("Backup restaurado")
            }
        } message: {
            Text(restoreMessage)
        }
        .alert("Apagar todo o histórico?", isPresented: $confirmClear) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar", role: .destructive) {
                store.clearHistory()
                Haptics.play("warning")
                store.showToast("Histórico apagado")
            }
        } message: {
            Text("Sessões, estatísticas e nível estimado serão apagados deste aparelho. Os ajustes continuam.")
        }
    }

    private let qTimeOptions: [PFSegmented<Int>.Option] = [
        PFSegmented<Int>.Option(value: 0, title: "Sem limite"),
        PFSegmented<Int>.Option(value: 30, title: "30 s"),
        PFSegmented<Int>.Option(value: 60, title: "60 s"),
        PFSegmented<Int>.Option(value: 90, title: "90 s"),
    ]

    private func feedbackRow(_ opt: (String, String, String), on: Bool) -> some View {
        HStack(alignment: .top, spacing: PF.Space.m) {
            ZStack {
                Circle().stroke(on ? PF.acc : PF.line, lineWidth: 2).frame(width: 22, height: 22)
                if on { Circle().fill(PF.acc).frame(width: 12, height: 12).transition(.scale) }
            }
            .padding(.top, 2)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(opt.1).pfText(.body, weight: .semibold).foregroundColor(PF.ink)
                Text(opt.2).pfText(.footnote).foregroundColor(PF.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, PF.Space.xs)
        .contentShape(Rectangle())
    }

    private var restoreMessage: String {
        guard let b = pendingBackup else { return "" }
        var t = "Psicotécnico: o histórico atual (\(store.db.sessions.count) sessões) será substituído por \(b.sessions.count) sessões do backup."
        if let p = b.palografico {
            t += " Palográfico: o histórico atual (\(paloStore.records.count) sessões) será substituído por \(p.records.count) sessões do backup."
        } else {
            t += " Este backup não tem dados do Palográfico; o histórico do Palográfico fica como está."
        }
        return t
    }

    private func binding(_ key: WritableKeyPath<PsicoSettings, Bool>) -> Binding<Bool> {
        Binding(get: { store.settings[keyPath: key] }, set: { v in
            Haptics.play("selection")
            store.updateSettings { $0[keyPath: key] = v }
        })
    }

    private func stage(_ data: Data) {
        if let b = store.parseBackup(data) {
            pendingBackup = b
        } else {
            Haptics.play("error")
            store.showToast("Esse texto não é um backup válido.")
        }
    }

    private func importFromClipboard() {
        guard let text = UIPasteboard.general.string, let data = text.data(using: .utf8) else {
            store.showToast("Não há texto copiado.")
            return
        }
        stage(data)
    }

    private func exportBackup() {
        guard let data = store.backupData(palo: paloStore) else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("psicofun-backup-\(fmt.string(from: Date())).json")
        do { try data.write(to: url, options: .atomic) } catch { return }
        Haptics.play("light")
        PsicoShare.present([url])
    }
}

/// Folha de compartilhar do iOS, apresentada pelo controlador do topo.
enum PsicoShare {
    static func present(_ items: [Any]) {
        guard let root = (UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        top.present(vc, animated: true)
    }
}
