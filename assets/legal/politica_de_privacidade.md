# Política de Privacidade do UauGo

Versão 1.15, de 24/10/2026 (controles de música no mapa, com o acesso a notificações usado só no celular; versão 1.14: placa do veículo e contato de emergência, guardados só no celular; versão 1.13: estatísticas anônimas de uso e relatório de erros, que podem ser desligados; versão 1.12: alerta "veículo parado no acostamento" passa a ser automático, sem identificar o usuário; versão 1.11: pedidos falados livres interpretados por IA; versão 1.10: alerta opcional "veículo parado no acostamento"; versão 1.9: pesquisa de trajeto por voz, opcional; versão 1.8: a posição só é enviada com o App fora da tela se você ligar a opção "Compartilhar posição em segundo plano").

Esta Política explica quais dados pessoais o aplicativo **UauGo** ("App") trata, para quê, com quem compartilha, por quanto tempo guarda e como você exerce seus direitos, conforme a **Lei Geral de Proteção de Dados (Lei 13.709/2018, "LGPD")**.

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
- **Em uma expedição:** sua posição, velocidade e horário são enviados aos **participantes da expedição** (no máximo 1 vez por minuto) enquanto ela estiver aberta no App. Com o App minimizado ou a tela apagada, a posição só continua sendo enviada se você ligar a opção **"Compartilhar posição em segundo plano"** (Configurações → Tela; vem desligada), e então aparece a notificação fixa "UauGo ativo". Fora de uma expedição, sua posição não é enviada ao grupo nem guardada no servidor. Base legal: consentimento (art. 7º, I), dado na tela de autorizações e ao entrar na expedição.
- **SOS:** sua posição é enviada aos participantes da expedição.
- **Alerta reportado:** a posição do alerta e o identificador de quem reportou ficam visíveis aos usuários durante a validade do alerta.

**Perfil exibido ao grupo**
- Nome de piloto, marca, modelo, tipo e cor do veículo e a **foto do veículo** (se você enviar). Finalidade: mostrar quem é quem no mapa da expedição.

**Clube (opcional, só com sua autorização)**
- Cada clube tem **administradores**, habilitados com códigos de ativação fornecidos pela HelpAITech. Para entrar, cada membro usa um **convite de uso único** gerado por um administrador. Guardamos quem são os administradores e **quem convidou cada membro**, para garantir que só membros oficiais participem. Administradores podem remover membros. A HelpAITech pode pré-cadastrar o **nome** de clubes conhecidos; eles só aparecem no App depois que um administrador do próprio clube ativa o acesso.
- **Cidade base** arredondada a ~1 km, nome e clube. Outros membros veem apenas o nome, a cidade e a distância aproximada, **nunca sua posição exata**.
- **Telefone:** fica **só no seu celular** e é enviado apenas quando você pede ajuda ou avisa alguém e marca essa opção.

**Comandos de voz (opcional, desligado por padrão)**
- Se você ligar em Configurações → Acessibilidade, o App usa o **microfone** com o mapa aberto para reconhecer comandos como "UauGo, radar" e as respostas "sim"/"não". O reconhecimento é feito **no próprio celular** (sem internet): **o áudio não é gravado, não é guardado e não sai do aparelho**. Só os comandos reconhecidos viram ações (por exemplo, um alerta). Você pode desligar a qualquer momento. Base legal: consentimento (art. 7º, I).
- **"Veículo parado no acostamento" (automático):** com o App em uso, quando você ficar parado mais de 2 minutos no acostamento de uma rodovia, o App publica um alerta temporário "veículo parado" naquele ponto para quem vem atrás. O alerta **não mostra quem você é** (nem nome, nem veículo); fica só o ponto e o horário. Ele some quando você volta a andar ou em até 30 minutos, e você pode tirá-lo na hora tocando em "Não avisar" no aviso que aparece na tela. Base legal: proteção da vida e da incolumidade física de terceiros (art. 7º, VII) e legítimo interesse na segurança viária (art. 7º, IX).
- **Pedidos falados livres (IA):** quando você pede por voz algo fora da lista de comandos (ex.: "um restaurante bom e barato"), o **texto** do pedido (não o áudio) é enviado ao **Gemini, do Google**, pelo servidor do App, só para entender o que procurar. Não é usado para outra finalidade e não é guardado pelo App.
- **Pesquisa de trajeto por voz (opcional, desligada):** se você ligar, ao dizer "UauGo, ir para" o App ouve o destino com o **reconhecimento de voz do Android**. Quando o celular oferece reconhecimento no próprio aparelho, o áudio **não sai do celular**; se não oferecer, o áudio dessa frase é enviado ao **Google**, que o transforma em texto (sujeito à política de privacidade do Google). O App usa o texto apenas para pesquisar o lugar e não guarda o áudio. Base legal: consentimento (art. 7º, I).

**Estatísticas de uso e relatório de erros (pode desligar)**
- **Estatísticas anônimas de uso** (Google Analytics para Firebase): quantas pessoas usam o App por dia, semana e mês, por quanto tempo voltam a usar, quais recursos são usados (traçar rota, Só dirigir, criar ou entrar em expedição, marcar alerta, comando de voz), modelo do celular, versão do Android e do App, e região aproximada (cidade/estado, estimada pelo endereço de internet). **Não inclui** sua localização exata, nome, e-mail, trajetos nem o conteúdo das expedições, e **não coletamos o identificador de anúncios** nem usamos esses dados para publicidade.
- **Relatório de erros** (Firebase Crashlytics): quando o App trava ou dá erro, envia o que aconteceu (a parte do programa que falhou), o modelo do celular e as versões, para corrigirmos.
- Finalidade: entender o uso e melhorar o App. Base legal: legítimo interesse (art. 7º, IX). **Você pode desligar** a qualquer momento em Configurações → "Compartilhar estatísticas de uso".

**Notificações**
- Token de notificações do celular (Firebase Cloud Messaging). Finalidade: avisar SOS e paradas do grupo e mensagens do clube.

**Controles de música no mapa (opcional, desligado por padrão)**
- Se você ligar em Configurações e liberar o **"Acesso a notificações"** do Android, o App lê **só a música que está tocando** (título, artista e capa, de apps como Spotify, YouTube Music ou Deezer) para mostrar o mini player e enviar os comandos anterior / tocar-pausar / próxima. Isso acontece **apenas no celular**: nada é enviado ao nosso servidor nem guardado, e o App **não lê o conteúdo das suas notificações**. Você pode desligar a opção ou retirar o acesso nas configurações do Android a qualquer momento. Base legal: consentimento (art. 7º, I).

**Dados que ficam só no celular**
- Histórico de viagens (caminho, estatísticas, gastos), viagens planejadas, configurações, consumo do veículo, telefone, **placa do veículo** (usada só para avisar do rodízio) e **contato de emergência** (nome e WhatsApp, usado só quando você toca no SOS). **Não temos acesso a eles.** Desinstalar o App apaga esses dados.

## 4. Com quem compartilhamos

- **Outros usuários**, apenas o descrito acima (participantes da sua expedição, membros do seu clube e alertas públicos).
- **Operadores (prestadores de serviço):** Google LLC (Firebase: banco de dados, arquivos, login, notificações, funções, estatísticas de uso e relatório de erros; Google Maps, Directions e Places) e Open-Meteo (previsão do tempo, só coordenadas, sem identificação).
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
- **Estatísticas de uso:** os detalhes por evento, por **2 meses**; depois ficam só os totais (sem identificar ninguém).
- **Relatórios de erro:** **90 dias**.
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
