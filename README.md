# PsicoFun

App de treino para psicotécnico no iOS: sequências, matrizes, analogias, rotação e figura intrusa. Cada questão é gerada na hora a partir de regras e verificada por um solucionador, então só existe uma resposta certa.

## Instalar e atualizar (sideload)

O app é compilado pelo GitHub Actions e publicado como `.ipa` **não assinado**, para ser assinado pelo seu app de sideload (FlareStore, AltStore, SideStore, Feather, ESign etc.).

### Link da fonte (adicione uma vez)

```
https://raw.githubusercontent.com/oEduRibeiro/PsicoFun/main/altstore/apps.json
```

Adicionando essa fonte, toda nova versão aparece sozinha como atualização no seu app de sideload.

- **FlareStore / Feather / ESign:** abra a aba de fontes (Sources/Repos), toque em **+** / **Adicionar fonte** e cole o link acima.
- **AltStore:** abra no iPhone [altstore://source?url=https://raw.githubusercontent.com/oEduRibeiro/PsicoFun/main/altstore/apps.json](altstore://source?url=https://raw.githubusercontent.com/oEduRibeiro/PsicoFun/main/altstore/apps.json) ou vá em *Sources → +* e cole o link.
- **SideStore:** abra no iPhone [sidestore://source?url=https://raw.githubusercontent.com/oEduRibeiro/PsicoFun/main/altstore/apps.json](sidestore://source?url=https://raw.githubusercontent.com/oEduRibeiro/PsicoFun/main/altstore/apps.json) ou vá em *Sources → +* e cole o link.

### Baixar o .ipa direto

Sempre a versão mais recente:

```
https://github.com/oEduRibeiro/PsicoFun/releases/latest/download/PsicoFun.ipa
```

Todas as versões ficam em [Releases](https://github.com/oEduRibeiro/PsicoFun/releases).

## Como uma atualização é publicada

1. Um commit em `main` que mexa em `ios/` (ou um disparo manual em *Actions → iOS (.ipa) → Run workflow*) inicia o build num Mac do GitHub.
2. O workflow gera o projeto com XcodeGen, compila sem assinatura e empacota `PsicoFun.ipa`.
3. Cria a release `v1.0.N` (N = número da execução) com o `.ipa` anexado.
4. Atualiza `altstore/apps.json` com a nova versão, e os apps de sideload passam a oferecer a atualização.

Pull requests também compilam o `.ipa` (disponível como artefato da execução), mas não publicam release.

Para mudar a versão base (ex.: `1.1`), edite `ios/VERSION`.

## Estrutura

```
ios/
  project.yml            # projeto Xcode (XcodeGen)
  PsicoFun/              # app nativo em Swift (UIKit + WKWebView)
  Web/index.html         # motor de questões e interface, empacotados no app (funciona offline)
altstore/
  apps.json              # fonte para AltStore/SideStore/FlareStore (atualizada pelo workflow)
  icon.png
scripts/update_source.py # atualiza a fonte a cada release
.github/workflows/ios.yml
```

O app nativo cuida de: dados salvos no aparelho (arquivo próprio, além do armazenamento do WebView), vibração ao escolher e confirmar, exportação de backup pela folha de compartilhar do iOS, áreas seguras (notch e barra inferior) e links externos no Safari.

## Compilar localmente (opcional, precisa de um Mac)

```sh
brew install xcodegen
cd ios && xcodegen generate && open PsicoFun.xcodeproj
```
