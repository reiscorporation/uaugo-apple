# Material para a App Store e o Google Play

Textos prontos para colar nos consoles. Revise os trechos entre colchetes.

---

## 1. Textos do app

| Campo | Texto | Limite |
|---|---|---|
| Nome | Comboio: moto em grupo | 30 |
| Subtítulo (Apple) | Expedições de moto em comboio | 30 |
| Descrição curta (Google) | Comboio no mapa, paradas, SOS e alertas de perigo para viagens de moto em grupo. | 80 |
| Palavras-chave (Apple) | moto,motociclismo,expedição,viagem,motoclube,grupo,rota,SOS,estrada,mototurismo,motoqueiro,trilha | 100 |
| Categoria | Mapas e navegação (Google) · Navegação (Apple) | |

### Descrição completa

Viajar de moto em grupo ficou mais seguro e organizado.

O Comboio mostra no mapa, em tempo real, onde está cada piloto da sua expedição, com a foto da moto de cada um. Combine paradas, trace a rota pelas estradas e saiba na hora quando alguém ficou para trás.

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

**Para o motoclube**
- Peça ajuda ao membro do clube mais próximo
- Avise quando estiver passando pela cidade de alguém do clube
- Você decide quem pode te encontrar e te contatar

**Sua privacidade em primeiro lugar**
Sem cadastro de e-mail ou senha. Nenhuma autorização opcional vem ligada, e você pode excluir todos os seus dados pelo próprio app.

Importante: não manuseie o celular enquanto pilota. Pare em local seguro. Em emergência, ligue 192 (SAMU), 193 (Bombeiros) ou 191 (PRF).

---

## 2. Google Play: Segurança dos dados

Respostas gerais:

| Pergunta | Resposta |
|---|---|
| O app coleta ou compartilha dados do usuário? | Sim |
| Os dados são criptografados em trânsito? | Sim |
| O usuário pode pedir a exclusão dos dados? | Sim: no app (Privacidade e autorizações > Excluir todos os meus dados) e pelo e-mail [privacidade@seudominio.com.br] |
| Link para exclusão de dados (web) | [URL da página explicando como excluir, pode ser a seção 9 da política] |

Tipos de dados (marque como **coletado**; em "compartilhado" responda **não**, pois os envios a outros usuários são iniciados pelo próprio usuário e os prestadores de serviço não contam como compartilhamento, segundo as definições do Google; confira a orientação atual no formulário):

| Tipo de dado | Obrigatório? | Finalidade | Observação |
|---|---|---|---|
| Local exato | Obrigatório | Funcionalidade do app | Posição no comboio, SOS, pedido de ajuda |
| Local aproximado | Opcional | Funcionalidade do app | Cidade base do motoclube |
| Nome | Obrigatório | Funcionalidade do app | Nome de piloto |
| Número de telefone | Opcional | Funcionalidade do app | Processado de forma temporária (não armazenado) |
| Fotos | Opcional | Funcionalidade do app | Foto da moto |
| Outros conteúdos gerados pelo usuário | Opcional | Funcionalidade do app | Paradas, alertas de perigo, mensagens ao clube |
| IDs do dispositivo ou outros IDs | Obrigatório | Funcionalidade do app | Identificador anônimo e token de notificação |

---

## 3. Google Play: serviço em primeiro plano de localização

**Declaração (cole no formulário):**

> O Comboio é usado por grupos de motociclistas em viagem. Enquanto o usuário participa de uma expedição, o app usa um serviço em primeiro plano do tipo "location" para continuar enviando a posição do piloto aos demais membros do grupo, mesmo com a tela desligada ou o app minimizado. Isso permite que o grupo saiba onde cada integrante está durante a viagem e que um pedido de SOS mostre a posição correta. Uma notificação permanente ("Comboio ativo") fica visível durante todo o uso, e o serviço é encerrado quando o usuário sai da expedição.

**Roteiro do vídeo demonstrativo (30 a 60 segundos, gravação da tela):**
1. Abrir o app e entrar numa expedição.
2. Mostrar o mapa com outro piloto se movendo.
3. Minimizar o app e mostrar a notificação "Comboio ativo".
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

> O Comboio é um app para grupos de motociclistas em viagem.
>
> **Como testar:** abra o app em dois aparelhos (ou peça um código de teste: [CÓDIGO]). Aceite as autorizações. No primeiro aparelho, toque em "Criar e liderar"; no segundo, use o código exibido em "Entrar no comboio". Cada aparelho verá o outro no mapa.
>
> **Localização em segundo plano:** durante uma expedição, a posição continua sendo compartilhada com o grupo com o app minimizado, para que os pilotos saibam onde cada um está enquanto pilotam e para que o SOS mostre a posição correta. O indicador de localização do iOS fica visível, e a coleta termina quando o usuário sai da expedição.
>
> **Conta:** não há cadastro com e-mail ou senha (autenticação anônima). A exclusão de dados está em Privacidade e autorizações > Excluir todos os meus dados.
>
> **Conteúdo gerado por usuários:** fotos de motos e nomes ficam visíveis apenas para os membros das expedições e motoclubes privados (acesso por código). Alertas de perigo não exibem o autor.

---

## 6. Pontos de atenção antes do envio

- **Conteúdo gerado por usuários (Apple, diretriz 1.2):** apps com conteúdo de usuários podem precisar de forma de denunciar e bloquear. Como fotos e nomes só aparecem em grupos privados, pode não ser exigido, mas se o revisor pedir, será preciso incluir "Denunciar foto" e "Bloquear usuário".
- **Classificação etária:** responda ao questionário; o app não tem violência, conteúdo adulto nem compras.
- **Capturas de tela:** mapa com o comboio, faixa de alerta de perigo, tela do motoclube, tela "Minha moto" e tela de autorizações.
- **Teste fechado no Google Play:** contas pessoais novas precisam de um período de teste fechado com testadores antes da produção. Confira a regra atual no Play Console.
