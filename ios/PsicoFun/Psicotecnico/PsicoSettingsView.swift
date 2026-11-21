import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PsicoSettingsView: View {
    @ObservedObject var store: PsicoStore

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
        Form {
            Section {
                ForEach(feedbackOptions.indices, id: \.self) { i in
                    let opt = feedbackOptions[i]
                    Button {
                        guard st.feedback != opt.0 else { return }
                        Haptics.play("selection")
                        store.updateSettings { $0.feedback = opt.0 }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(opt.1).foregroundColor(.primary).font(.body.weight(.semibold))
                                Text(opt.2).font(.subheadline).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundColor(PF.acc)
                                .opacity(st.feedback == opt.0 ? 1 : 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Toggle("Mostrar alternativa correta", isOn: binding(\.showCorrect))
                    .disabled(st.feedback != "eye")
            } header: {
                Text("Resposta nos modos de treino")
            } footer: {
                Text("Vale para Treino livre, Rampa, Adaptativo e Ponto fraco. O Simulado sempre mostra só no final. \"Mostrar alternativa correta\" pinta a certa e a errada ao confirmar, mesmo com a explicação escondida no olho.")
            }

            Section {
                Toggle("Mostrar cronômetro", isOn: binding(\.timer))
                Toggle("Mostrar o nível da questão", isOn: binding(\.showLevel))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tempo limite por questão (treino)")
                    Picker("Tempo limite por questão", selection: Binding(get: { st.qTime }, set: { v in
                        Haptics.play("selection")
                        store.updateSettings { $0.qTime = v }
                    })) {
                        Text("Sem limite").tag(0)
                        Text("30 s").tag(30)
                        Text("60 s").tag(60)
                        Text("90 s").tag(90)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 4)
            } header: {
                Text("Durante a questão")
            }

            Section {
                Button { exportBackup() } label: { Label("Exportar backup", systemImage: "square.and.arrow.up") }
                Button { importChoice = true } label: { Label("Restaurar backup", systemImage: "arrow.counterclockwise") }
                Button(role: .destructive) { confirmClear = true } label: { Label("Apagar histórico", systemImage: "trash") }
            } header: {
                Text("Seus dados")
            } footer: {
                Text("Salvo neste aparelho · \(store.db.sessions.count) sessões guardadas. Para levar o histórico para outro aparelho, exporte o backup e restaure lá.")
            }

            Section {
                DisclosureGroup("Como as questões são feitas") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Cada questão nasce de regras, não de desenho livre: o gerador sorteia atributos (forma, quantidade, tamanho, preenchimento, rotação, posição, linhas) e regras para eles (progressão, alternância, ciclo, distribuição de três, soma, subtração, união e diferença de linhas), no modelo das matrizes de Raven.")
                        Text("Antes de aparecer, um solucionador separado tenta todas as regras possíveis em cada atributo. Se mais de uma resposta for defensável, a questão é descartada. As alternativas erradas mudam um ou mais atributos de forma equilibrada, para que a correta não se destaque por “ser a mais parecida com as outras”. Cada alternativa errada guarda qual regra ela viola — é assim que o relatório sabe o que você mais erra.")
                        Text("A mesma semente gera sempre a mesma questão, por isso a revisão de sessões antigas mostra exatamente o que você viu.")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                }
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
                if let b = pendingBackup { store.restore(b) }
                pendingBackup = nil
                Haptics.play("success")
                store.showToast("Backup restaurado")
            }
        } message: {
            Text("O histórico atual (\(store.db.sessions.count) sessões) será substituído por \(pendingBackup?.sessions.count ?? 0) sessões do backup.")
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
        guard let data = store.backupData() else { return }
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
