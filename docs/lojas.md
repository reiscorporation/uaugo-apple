# Material para a App Store e o Google Play

Textos prontos para colar nos consoles. Revise os trechos entre colchetes.

---

## 1. Textos do app

| Campo | Texto | Limite |
|---|---|---|
| Nome | Convoyar: viagem em grupo | 30 |
| Subtítulo (Apple) | Expedições de moto em comboio | 30 |
| Descrição curta (Google) | Convoyar no mapa, paradas, SOS e alertas de perigo para viagens de moto em grupo. | 80 |
| Palavras-chave (Apple) | moto,motociclismo,expedição,viagem,clube,grupo,rota,SOS,estrada,mototurismo,motoqueiro,trilha | 100 |
| Categoria | Mapas e navegação (Google) · Navegação (Apple) | |

### Descrição completa

Viajar de moto em grupo ficou mais seguro e organizado.

O Convoyar mostra no mapa, em tempo real, onde está cada piloto da sua expedição, com a foto da moto de cada um. Combine paradas, trace a rota pelas estradas e saiba na hora quando alguém ficou para trás.

**Para o grupo**
- Crie uma expedição e convide os amigos com um código
- Veja a posição e a velocidade de todos no mapa
- Marque paradas (posto, almoço, mirante, pernoite) e todos recebem a rota
- Funciona com sinal fraco: o que você fizer sem internet é enviado quando o sinal voltar

**Para a segurança**
- Botão SOS: segure para avisar o grupo com sua localização exata
- Alertas da comunidade: polícia, buraco, óleo na pista, animal, acidente e neblina
- Aviso sonoro quando você se aproxima de um perigo à frente
- Botões grandes, pensados para uso com luvas

**Para o clube**
- Peça ajuda ao membro do clube mais próximo
- Avise quando estiver passando pela cidade de alguém do clube
- Você decide quem pode te encontrar e te contatar

**Sua privacidade em primeiro lugar**
Para navegar sozinho não precisa de cadastro; para o grupo, entre com Google ou e-mail. Nenhuma autorização opcional vem ligada, e você pode excluir todos os seus dados pelo próprio app.

Importante: não manuseie o celular enquanto pilota. Pare em local seguro. Em emergência, ligue 192 (SAMU), 193 (Bombeiros) ou 191 (PRF).

---

## 2. Google Play: Segurança dos dados

Respostas gerais:

| Pergunta | Resposta |
|---|---|
| O app coleta ou compartilha dados do usuário? | Sim |
| Os dados são criptografados em trânsito? | Sim |
| O usuário pode pedir a exclusão dos dados? | Sim: no app (Privacidade e autorizações > Excluir todos os meus dados) e pelo e-mail helpaitech.ricardo@gmail.com |
| Link para exclusão de dados (web) | https://helpaitechcomboio.web.app/excluir-dados |

Tipos de dados (marque como **coletado**; em "compartilhado" responda **não**, pois os envios a outros usuários são iniciados pelo próprio usuário e os prestadores de serviço não contam como compartilhamento, segundo as definições do Google; confira a orientação atual no formulário):

| Tipo de dado | Obrigatório? | Finalidade | Observação |
|---|---|---|---|
| Local exato | Obrigatório | Funcionalidade do app | Posição no comboio, SOS, pedido de ajuda |
| Local aproximado | Opcional | Funcionalidade do app | Cidade base do clube |
| Nome | Obrigatório | Funcionalidade do app | Nome de piloto |
| Número de telefone | Opcional | Funcionalidade do app | Processado de forma temporária (não armazenado) |
| Fotos | Opcional | Funcionalidade do app | Foto da moto |
| Outros conteúdos gerados pelo usuário | Opcional | Funcionalidade do app | Paradas, alertas de perigo, mensagens ao clube |
| IDs do dispositivo ou outros IDs | Obrigatório | Funcionalidade do app | Identificador anônimo e token de notificação |

> **Áudio (comandos de voz):** NÃO marque "Gravações de voz ou som". O microfone só é usado se o usuário ligar a função, e o reconhecimento é feito no aparelho: o áudio não é coletado nem enviado (processamento no dispositivo não conta como coleta para o Google Play). Na permissão RECORD_AUDIO, a justificativa é: comandos de voz para marcar alertas sem tocar na tela (acessibilidade para quem pilota de luva).

---

## 3. Google Play: serviço em primeiro plano de localização

**Declaração (cole no formulário):**

> O Convoyar é usado por grupos de motociclistas em viagem. Enquanto o usuário participa de uma expedição ou navega até um destino com instruções por voz, o app usa um serviço em primeiro plano do tipo "location" para continuar enviando a posição do piloto aos demais membros do grupo e dando os avisos de navegação, mesmo com a tela desligada ou o app minimizado. Fora disso (por exemplo, no modo "Só dirigir"), a localização para quando o app sai da tela; o serviço também é encerrado se o app for fechado ou se o piloto ficar parado por 15 minutos com o app minimizado. Isso permite que o grupo saiba onde cada integrante está durante a viagem e que um pedido de SOS mostre a posição correta. Uma notificação permanente ("Convoyar ativo") fica visível durante todo o uso, e o serviço é encerrado quando o usuário sai da expedição.

**Roteiro do vídeo demonstrativo (30 a 60 segundos, gravação da tela):**
1. Abrir o app e entrar numa expedição.
2. Mostrar o mapa com outro piloto se movendo.
3. Minimizar o app e mostrar a notificação "Convoyar ativo".
4. Bloquear a tela, desbloquear e mostrar que a posição continuou atualizando no outro aparelho.
5. Sair da expedição e mostrar que a notificação desapareceu.

Publique o vídeo como "não listado" no YouTube e cole o link.

---

## 4. App Store: privacidade do app (App Privacy)

| Tipo de dado | Coletado | Vinculado ao usuário | Rastreamento | Finalidade |
|---|---|---|---|---|
| Localização exata | Sim | Sim (ID anônimo) | Não | Funcionalidade do app |
| Localização aproximada | Sim | Sim | Não | Funcionalidade do app |
| Nome | Sim | Sim | Não | Funcionalidade do app |
| Número de telefone | Sim (opcional) | Sim | Não | Funcionalidade do app |
| Fotos | Sim (opcional) | Sim | Não | Funcionalidade do app |
| Outro conteúdo do usuário | Sim | Sim | Não | Funcionalidade do app |
| ID do usuário | Sim | Sim | Não | Funcionalidade do app |
| ID do dispositivo | Sim | Sim | Não | Funcionalidade do app |

"Rastreamento" (tracking) é **Não**: o app não usa dados para publicidade nem os cruza com dados de outras empresas.

---

## 5. App Store: notas para o revisor

> O Convoyar é um app para grupos de motociclistas em viagem.
>
> **Como testar:** abra o app em dois aparelhos (ou peça um código de teste: [CÓDIGO]). Aceite as autorizações. No primeiro aparelho, toque em "Criar e liderar"; no segundo, use o código exibido em "Entrar no comboio". Cada aparelho verá o outro no mapa.
>
> **Localização em segundo plano:** durante uma expedição, a posição continua sendo compartilhada com o grupo com o app minimizado, para que os pilotos saibam onde cada um está enquanto pilotam e para que o SOS mostre a posição correta. O indicador de localização do iOS fica visível, e a coleta termina quando o usuário sai da expedição.
>
> **Conta:** navegar sozinho não exige cadastro; expedições, alertas e clube exigem entrar com Apple, Google ou e-mail. [Informe aqui um e-mail e senha de teste.] A exclusão de dados está em Privacidade e autorizações > Excluir todos os meus dados.
>
> **Conteúdo gerado por usuários:** fotos de motos e nomes ficam visíveis apenas para os membros das expedições e clubes privados (acesso por código). Alertas de perigo não exibem o autor.

---

## 6. Pontos de atenção antes do envio

- **Conteúdo gerado por usuários (Apple, diretriz 1.2):** apps com conteúdo de usuários podem precisar de forma de denunciar e bloquear. Como fotos e nomes só aparecem em grupos privados, pode não ser exigido, mas se o revisor pedir, será preciso incluir "Denunciar foto" e "Bloquear usuário".
- **Classificação etária:** responda ao questionário; o app não tem violência, conteúdo adulto nem compras.
- **Capturas de tela:** mapa com o comboio, faixa de alerta de perigo, tela do clube, tela "Minha moto" e tela de autorizações.
- **Teste fechado no Google Play:** contas pessoais novas precisam de um período de teste fechado com testadores antes da produção. Confira a regra atual no Play Console.

---

## 7. Links públicos (Firebase Hosting)

Gerados de `assets/legal/` por `node scripts/gerar-paginas.js` e publicados com
`firebase deploy --only hosting`. Mudou o texto no app? Gere e publique de novo.

| Uso no console | Link |
|---|---|
| Política de Privacidade | https://helpaitechcomboio.web.app/privacidade |
| Termos de Uso | https://helpaitechcomboio.web.app/termos |
| Exclusão de conta e dados | https://helpaitechcomboio.web.app/excluir-dados |

## 8. Assinatura e envio para a Google Play

- **Conta Google Play:** pessoal, ID 6256935240609624046.
- **Chave de upload:** `E:\APP\comboio-chaves\comboio-upload.jks` (alias `upload`;
  senha no `LEIA-ME` da mesma pasta). Fica FORA do git. Guarde uma cópia no
  Drive da HelpAITech. `android/key.properties` aponta para ela.
  - SHA-1: `AE:BB:4C:DB:A3:08:92:CA:CC:23:45:1A:77:37:AA:26:1D:0A:52:C0`
  - Já cadastrada no Firebase e na chave "Comboio Android" do mapa.
- **Gerar o pacote:** `flutter build appbundle --release --dart-define-from-file=config/dart_defines.json`
  → `build/app/outputs/bundle/release/app-release.aab`. A cada envio, aumente
  o número depois do `+` em `version:` no `pubspec.yaml`.
- **Depois do 1º envio:** a Play cria a **chave de assinatura do app** (Play
  Console → Testar e lançar → Configuração → Integridade do app → Assinatura do
  app). Copie o SHA-1 e o SHA-256 dela e cadastre no Firebase (Configurações do
  projeto → app Android → Adicionar impressão digital) e na chave "Comboio
  Android" (Google Cloud → Credenciais). Sem isso, na versão baixada da loja o
  login com Google falha e o mapa fica cinza.
- **App Check (já exigido no servidor):** vincule o projeto do Google Cloud
  `helpaitechcomboio` em Play Console → Testar e lançar → Integridade do app →
  Play Integrity API → **Vincular projeto do Cloud**. Sem isso, quem baixar da
  loja é recusado pelo servidor.
- **Teste fechado:** contas pessoais novas precisam de 12 testadores por 14
  dias seguidos antes da produção.