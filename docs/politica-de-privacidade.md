# Política de Privacidade do Convoyar

Versão 1.6, de 07/10/2026 (o app passou a se chamar Convoyar; antes, "RodaJunto" e "Comboio").

Esta Política explica quais dados pessoais o aplicativo **Convoyar** ("App") trata, para quê, com quem compartilha, por quanto tempo guarda e como você exerce seus direitos, conforme a **Lei Geral de Proteção de Dados (Lei 13.709/2018, "LGPD")**.

## 1. Quem é o responsável

- **Controlador:** Ricardo Reis, pessoa física, sob a marca HelpAITech.
- **Encarregado (contato para privacidade):** Ricardo Reis — **helpaitech.ricardo@gmail.com**.

## 2. Princípio do App: o mínimo possível no servidor

O que dá para ficar no seu celular fica no seu celular: **histórico de viagens, configurações, telefone, gastos e os dados de radares e limites**. No servidor fica só o que precisa ser compartilhado ao vivo com outras pessoas (expedição em andamento, alertas da comunidade e clube).

## 3. Dados tratados e finalidades

**Identificação da conta**
- Identificador gerado pelo Firebase (login anônimo) e, se você entrar com Google ou e-mail, seu **nome e e-mail**. Finalidade: identificar sua conta, impedir abusos e permitir recuperar o acesso. Base legal: execução do contrato (art. 7º, V).
- Registro do **aceite dos Termos** e das **autorizações** (versão, data e hora). Finalidade: comprovar o aceite. Base legal: cumprimento de obrigação legal e exercício regular de direitos (art. 7º, II e VI).

**Localização (GPS)**
- **Navegando sozinho ou em "Só dirigir":** a localização é usada **apenas no celular** (rota, avisos, velocímetro). Ela **não é enviada ao nosso servidor**. Para calcular a rota e buscar lugares, os pontos necessários (origem, destino, paradas e o texto da busca) passam pelo nosso servidor, que os repassa ao Google **sem guardá-los**; para a previsão do tempo, os pontos à frente são enviados ao Open-Meteo.
- **Em uma expedição:** sua posição, velocidade e horário são enviados aos **participantes da expedição** (no máximo 1 vez por minuto) enquanto ela estiver aberta, inclusive com o App minimizado (notificação fixa "Convoyar ativo"). Base legal: consentimento (art. 7º, I), dado na tela de autorizações e ao entrar na expedição.
- **SOS:** sua posição é enviada aos participantes da expedição.
- **Alerta reportado:** a posição do alerta e o identificador de quem reportou ficam visíveis aos usuários durante a validade do alerta.

**Perfil exibido ao grupo**
- Nome de piloto, marca, modelo, tipo e cor do veículo e a **foto do veículo** (se você enviar). Finalidade: mostrar quem é quem no mapa da expedição.

**Clube (opcional, só com sua autorização)**
- Cada clube tem **administradores**, habilitados com códigos de ativação fornecidos pela HelpAITech. Para entrar, cada membro usa um **convite de uso único** gerado por um administrador. Guardamos quem são os administradores e **quem convidou cada membro**, para garantir que só membros oficiais participem. Administradores podem remover membros. A HelpAITech pode pré-cadastrar o **nome** de clubes conhecidos; eles só aparecem no App depois que um administrador do próprio clube ativa o acesso.
- **Cidade base** arredondada a ~1 km, nome e clube. Outros membros veem apenas o nome, a cidade e a distância aproximada, **nunca sua posição exata**.
- **Telefone:** fica **só no seu celular** e é enviado apenas quando você pede ajuda ou avisa alguém e marca essa opção.

**Comandos de voz (opcional, desligado por padrão)**
- Se você ligar em Configurações → Acessibilidade, o App usa o **microfone** com o mapa aberto para reconhecer comandos como "roda junto radar" e as respostas "sim"/"não". O reconhecimento é feito **no próprio celular** (sem internet): **o áudio não é gravado, não é guardado e não sai do aparelho**. Só os comandos reconhecidos viram ações (por exemplo, um alerta). Você pode desligar a qualquer momento. Base legal: consentimento (art. 7º, I).

**Notificações**
- Token de notificações do celular (Firebase Cloud Messaging). Finalidade: avisar SOS e paradas do grupo e mensagens do clube.

**Dados que ficam só no celular**
- Histórico de viagens (caminho, estatísticas, gastos), configurações, consumo do veículo e telefone. **Não temos acesso a eles.** Desinstalar o App apaga esses dados.

## 4. Com quem compartilhamos

- **Outros usuários**, apenas o descrito acima (participantes da sua expedição, membros do seu clube e alertas públicos).
- **Operadores (prestadores de serviço):** Google LLC (Firebase: banco de dados, arquivos, login, notificações e funções; Google Maps, Directions e Places) e Open-Meteo (previsão do tempo, só coordenadas, sem identificação).
- **Autoridades**, quando houver obrigação legal ou ordem judicial.
- **Não vendemos** dados pessoais e não os usamos para publicidade.

## 5. Onde os dados ficam

O banco de dados, os arquivos e as funções do servidor ficam na região **São Paulo (southamerica-east1)** do Google Cloud. Alguns serviços do Google (como mapas, rotas e notificações) podem tratar dados em servidores fora do Brasil, com as garantias previstas nos contratos do Google, conforme o art. 33 da LGPD.

## 6. Por quanto tempo guardamos

- **Expedição** (participantes, posições, paradas, SOS): até o líder encerrar ou após **30 dias sem atividade**.
- **Alertas da comunidade:** pela validade de cada tipo (de **1 hora a 7 dias**), e depois apagados automaticamente.
- **Avisos do clube:** **180 dias**.
- **Convites do clube:** até vencerem (**7 dias**), e depois apagados automaticamente.
- **Conta, autorizações e aceite dos Termos:** enquanto a conta existir.
- **Contagem diária de consultas de rotas e lugares** (só o número, para limitar abusos): substituída a cada dia.
- **Dados no celular:** até você excluir ou desinstalar o App.

## 7. Seus direitos (art. 18 da LGPD)

Você pode: confirmar se tratamos seus dados; acessar, corrigir ou atualizar seus dados; pedir anonimização, bloqueio ou eliminação; pedir a portabilidade; saber com quem compartilhamos; **revogar o consentimento** a qualquer momento; e se opor a tratamentos.

- **No próprio App:** "Privacidade e autorizações" permite mudar as autorizações e **excluir todos os seus dados** (servidor e celular) imediatamente.
- **Por e-mail:** helpaitech.ricardo@gmail.com. Respondemos em até **15 dias**.
- Você também pode reclamar à **Autoridade Nacional de Proteção de Dados (ANPD)**.

## 8. Segurança

Usamos conexões criptografadas, regras de acesso no banco de dados (cada pessoa só lê o que lhe é permitido), verificação do aplicativo (App Check) e apagamento automático de dados antigos. Nenhum sistema é 100% seguro: em caso de incidente relevante, comunicaremos os afetados e a ANPD, como manda a lei.

## 9. Como excluir seus dados

No App: **Privacidade e autorizações → Excluir todos os meus dados**. Isso apaga sua conta, suas participações em expedições, seu cadastro no clube e os dados do celular. Os alertas que você reportou deixam de ser associados a você. Se não tiver mais o App, peça pelo e-mail helpaitech.ricardo@gmail.com.

## 10. Idade mínima

O App é destinado a maiores de **18 anos**. Não tratamos intencionalmente dados de crianças ou adolescentes.

## 11. Alterações

Podemos atualizar esta Política. Mudanças relevantes serão informadas no App, e, quando necessário, pediremos um novo consentimento.

## 12. Contato

**helpaitech.ricardo@gmail.com**
