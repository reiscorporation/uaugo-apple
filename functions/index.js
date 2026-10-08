/**
 * Cloud Functions do Convoyar (rodam no servidor do Firebase, região
 * southamerica-east1). Publicar: `firebase deploy --only functions`.
 *
 * Funções (detalhes em docs/ARQUITETURA.md, seção 5):
 * - onSos, onStop ............ push para o grupo ao criar SOS / parada
 * - endExpedition ............ o líder encerra a expedição (apaga tudo)
 * - clubNearby, clubNotify ... clube (membros próximos, avisos)
 * - createClub, createClubInvite, joinClub, setClubAdmin ... clube oficial:
 *                              administradores pelo código de ativação da
 *                              HelpAITech, convites de uso único (clubs.js)
 * - deleteMyData ............. exclusão de dados (LGPD)
 * - directions, places ....... rotas e busca de lugares (chave do Google só aqui;
 *                              functions/maps.js, limite diário por usuário)
 * - updateRadars ............. radares e trechos da PRF (seg. e qui.)
 * - updateSpeedLimits ........ limites de velocidade por estado (segunda)
 * - updatePois ............... lombadas, postos e pedágios (todo dia)
 * - cleanup .................. limpeza diária (expedições paradas etc.)
 *
 * Os dados públicos vão para o Storage (public/...) e a versão de cada
 * arquivo para meta/{radars,limits,pois}: o app só baixa quando muda.
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getStorage } = require("firebase-admin/storage");

const zlib = require("zlib");
const { buildRadarData } = require("./radars");
const { buildSpeedLimits } = require("./speedlimits");
const { buildPois } = require("./pois");
const maps = require("./maps");
const clubs = require("./clubs");

initializeApp();
const db = getFirestore();
const region = "southamerica-east1";

// Ative (true) em functions/.env depois de registrar o app no App Check.
const enforceAppCheck = process.env.ENFORCE_APP_CHECK === "true";
const callOpts = { region, enforceAppCheck };

/**
 * Exige conta de verdade (Google, Apple ou e-mail), não a anônima do
 * primeiro uso. Mesma regra do Firestore (hasAccount). Devolve o uid.
 */
function accountUid(req) {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Faça login.");
  if (req.auth.token?.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("permission-denied", "Entre com sua conta para usar esta função.");
  }
  return uid;
}

/**
 * Problema numa rotina que precisa de atenção humana: vai para o log com
 * gravidade ERROR e o prefixo [ALERTA]. O Cloud Monitoring manda um e-mail
 * para a HelpAITech (política "Convoyar - rotina com problema"; veja
 * docs/MANUTENCAO.md). Erros que derrubam a função também disparam o e-mail.
 */
function alerta(msg) {
  console.error(`[ALERTA] ${msg}`);
}

// No Emulator Suite (scripts/testar-local.ps1) não existe FCM local:
// em vez de enviar o push, só registra no log do emulador.
const noEmulador = process.env.FUNCTIONS_EMULATOR === "true";
function sendPush(message) {
  if (noEmulador) {
    console.log("[push simulado]", JSON.stringify(message.notification), "->",
      message.topic ? `tópico ${message.topic}` : "aparelho do membro");
    return Promise.resolve();
  }
  return getMessaging().send(message);
}

// ===================== Expedições =====================

// Push para todo o comboio quando alguém aperta SOS.
exports.onSos = onDocumentCreated(
  { document: "expeditions/{code}/alerts/{alertId}", region },
  async (event) => {
    const a = event.data?.data();
    if (!a) return;
    const { code, alertId } = event.params;
    await sendPush({
      topic: `exp_${code}`,
      notification: {
        title: "🚨 SOS no comboio",
        body: `${a.name} pediu ajuda! Toque para ver no mapa.`,
      },
      data: { type: "sos", code, alertId, lat: String(a.lat), lng: String(a.lng) },
      android: { priority: "high", notification: { sound: "default" } },
      apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default" } } },
    });
  }
);

// Avisa o grupo quando uma nova parada é adicionada.
exports.onStop = onDocumentCreated(
  { document: "expeditions/{code}/stops/{stopId}", region },
  async (event) => {
    const s = event.data?.data();
    if (!s) return;
    await sendPush({
      topic: `exp_${event.params.code}`,
      notification: { title: "📍 Nova parada", body: s.name },
      data: { type: "stop", code: event.params.code },
    });
  }
);

/**
 * O líder encerra a expedição para todos: apaga tudo do servidor (membros,
 * paradas, SOS). O histórico da viagem fica só no celular de cada piloto.
 */
exports.endExpedition = onCall(callOpts, async (req) => {
  const uid = accountUid(req);
  const code = req.data?.code;
  if (typeof code !== "string" || !/^[A-Z0-9]{6,8}$/.test(code)) {
    throw new HttpsError("invalid-argument", "Código inválido.");
  }
  const ref = db.doc(`expeditions/${code}`);
  const snap = await ref.get();
  if (!snap.exists) return { ok: true };
  if (snap.data().leaderId !== uid) {
    throw new HttpsError("permission-denied", "Só o líder pode encerrar a expedição.");
  }
  await db.recursiveDelete(ref);
  return { ok: true };
});

// ===================== Rotas e lugares (chave fica no servidor) ===========
// Detalhes em maps.js. O app chama estas funções no lugar do Google direto.
exports.directions = onCall(callOpts, maps.directions);
exports.places = onCall(callOpts, maps.places);

// ===================== Clube =====================

// Ativar (administrador, com código de ativação da HelpAITech), convidar,
// entrar (convite de uso único) e gerenciar administradores. Ver clubs.js.
exports.createClub = onCall(callOpts, (req) => clubs.createClub(accountUid(req), req.data));
exports.createClubInvite = onCall(callOpts, (req) => clubs.createClubInvite(accountUid(req), req.data));
exports.joinClub = onCall(callOpts, (req) => clubs.joinClub(accountUid(req), req.data));
exports.setClubAdmin = onCall(callOpts, (req) => clubs.setClubAdmin(accountUid(req), req.data));

const CONSENT_FOR = { help: "receiveHelp", passing: "receivePassing" };
const MAX_KM = 300;
const MAX_PER_HOUR = 5;

function distanceKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

async function memberOf(clubId, uid) {
  if (typeof clubId !== "string" || !clubId) {
    throw new HttpsError("invalid-argument", "Clube inválido.");
  }
  const m = await db.doc(`clubs/${clubId}/members/${uid}`).get();
  if (!m.exists) throw new HttpsError("permission-denied", "Você não é membro deste clube.");
  return m.data();
}

function validCoords(lat, lng) {
  return typeof lat === "number" && typeof lng === "number" &&
    Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
}

/**
 * Lista membros do clube que AUTORIZARAM o tipo de contato, ordenados por
 * distância da cidade base deles. Nunca devolve coordenadas: só cidade e
 * distância arredondada em km.
 */
exports.clubNearby = onCall(callOpts, async (req) => {
  const uid = accountUid(req);
  const { clubId, lat, lng, purpose } = req.data || {};
  if (!validCoords(lat, lng) || !CONSENT_FOR[purpose]) {
    throw new HttpsError("invalid-argument", "Dados inválidos.");
  }
  await memberOf(clubId, uid);

  const members = (await db.collection(`clubs/${clubId}/members`).get()).docs
    .filter((d) => d.id !== uid);
  const users = await Promise.all(members.map((d) => db.doc(`users/${d.id}`).get()));

  const results = [];
  users.forEach((u, i) => {
    const data = u.data();
    const c = data?.consent || {};
    if (!c.findable || !c[CONSENT_FOR[purpose]] || !data.base) return;
    const d = distanceKm(lat, lng, data.base.lat, data.base.lng);
    if (d > MAX_KM) return;
    const m = members[i].data();
    results.push({
      uid: u.id,
      name: m.name || "Membro",
      city: data.base.city || m.city || "",
      bike: m.bike || "",
      distanceKm: Math.max(1, Math.round(d)),
    });
  });
  results.sort((a, b) => a.distanceKm - b.distanceKm);
  return { members: results.slice(0, 15) };
});

/**
 * Envia pedido de ajuda ou aviso de passagem para um membro,
 * somente se ele autorizou esse tipo de contato. Limite: 5 envios/hora.
 */
exports.clubNotify = onCall(callOpts, async (req) => {
  const uid = accountUid(req);
  const { clubId, targetUid, type, lat, lng, message, phone } = req.data || {};
  if (!CONSENT_FOR[type] || typeof targetUid !== "string" || targetUid === uid) {
    throw new HttpsError("invalid-argument", "Dados inválidos.");
  }

  const sender = await memberOf(clubId, uid);
  await memberOf(clubId, targetUid);

  const target = (await db.doc(`users/${targetUid}`).get()).data() || {};
  const c = target.consent || {};
  if (!c.findable || !c[CONSENT_FOR[type]]) {
    throw new HttpsError("permission-denied", "Este membro não autorizou esse tipo de contato.");
  }
  if (!target.fcmToken) {
    throw new HttpsError("failed-precondition", "Este membro não pode receber notificações agora.");
  }

  // Limite de envios por hora (evita abuso).
  const rateRef = db.doc(`clubs/${clubId}/rate/${uid}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(rateRef);
    const now = Date.now();
    const recent = (snap.data()?.times || []).filter((t) => now - t < 3600e3);
    if (recent.length >= MAX_PER_HOUR) {
      throw new HttpsError("resource-exhausted", "Limite de avisos por hora atingido. Tente mais tarde.");
    }
    recent.push(now);
    tx.set(rateRef, { times: recent });
  });

  const isHelp = type === "help";
  const name = sender.name || "Um membro";
  let body = isHelp
    ? `${name}, do seu clube, precisa de ajuda perto de você.`
    : `${name}, do seu clube, está passando pela sua cidade.`;
  if (typeof message === "string" && message.trim()) {
    body += ` "${message.trim().slice(0, 140)}"`;
  }

  const data = { type: `club_${type}`, clubId, from: uid, name };
  if (isHelp && validCoords(lat, lng)) {
    data.lat = String(lat);
    data.lng = String(lng);
  }
  if (typeof phone === "string" && phone.trim()) data.phone = phone.trim().slice(0, 20);

  await sendPush({
    token: target.fcmToken,
    notification: {
      title: isHelp ? "🆘 Pedido de ajuda do clube" : "🏍️ Membro do clube de passagem",
      body,
    },
    data,
    android: { priority: "high", notification: { sound: "default" } },
    apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default" } } },
  });

  await db.collection(`clubs/${clubId}/notifications`).add({
    from: uid,
    to: targetUid,
    type,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

// ===================== Privacidade =====================

/**
 * Exclui os dados do usuário (art. 18 da LGPD). O app envia os códigos
 * das expedições e do clube que ele usou; o restante é encontrado pelo uid.
 */
exports.deleteMyData = onCall(callOpts, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Faça login.");
  const { expeditions, clubId } = req.data || {};
  const codes = Array.isArray(expeditions)
    ? expeditions.filter((c) => typeof c === "string" && /^[A-Z0-9]{6,8}$/.test(c)).slice(0, 50)
    : [];

  for (const code of codes) {
    const exp = db.doc(`expeditions/${code}`);
    const snap = await exp.get();
    if (!snap.exists) continue;
    if (snap.data().leaderId === uid) await exp.update({ leaderId: null });
    await exp.collection("members").doc(uid).delete();
    const alerts = await exp.collection("alerts").where("uid", "==", uid).get();
    await Promise.all(alerts.docs.map((d) => d.ref.delete()));
    const stops = await exp.collection("stops").where("createdBy", "==", uid).get();
    await Promise.all(stops.docs.map((d) => d.ref.update({ createdBy: null })));
  }

  if (typeof clubId === "string" && /^[A-Z0-9]{6,8}$/.test(clubId)) {
    const club = db.doc(`clubs/${clubId}`);
    const snap = await club.get();
    // Administrador excluindo os dados: sai da lista de administradores. Se
    // era o único, a HelpAITech gera um novo código de ativação para o clube.
    if (snap.exists) {
      const next = clubs.adminsOf(snap.data()).filter((a) => a !== uid);
      await club.update({ admins: next, createdBy: null, presidentId: null });
    }
    await club.collection("members").doc(uid).delete();
    await club.collection("rate").doc(uid).delete();
    const sent = await club.collection("notifications").where("from", "==", uid).get();
    const recv = await club.collection("notifications").where("to", "==", uid).get();
    await Promise.all([...sent.docs, ...recv.docs].map((d) => d.ref.delete()));
  }

  // Alertas de perigo continuam úteis para a comunidade, mas sem vínculo.
  const hazards = await db.collection("hazards").where("createdBy", "==", uid).get();
  await Promise.all(hazards.docs.map((d) => d.ref.update({ createdBy: "removido" })));

  await getStorage().bucket().deleteFiles({ prefix: `bikes/${uid}/` });
  await db.doc(`users/${uid}`).delete();
  await getAuth().deleteUser(uid);
  return { ok: true };
});

// ===================== Radares =====================

/**
 * Toda segunda e quinta: monta o arquivo de radares (fixos do Brasil +
 * trechos de radar portátil da PRF) e publica em public/radares.json.gz.
 * O app confere a versão em meta/radars (1 leitura) e só baixa se mudou.
 * Também pode ser rodada na hora pelo Cloud Scheduler ("Forçar execução").
 */
exports.updateRadars = onSchedule(
  {
    schedule: "every monday,thursday 05:00",
    timeZone: "America/Sao_Paulo",
    region,
    memory: "1GiB",
    timeoutSeconds: 900,
  },
  async () => {
    const data = await buildRadarData({ log: (m) => console.log(m) });
    if (data.radars.length < 1000) {
      throw new Error(`Poucos radares (${data.radars.length}); mantendo a versão anterior`);
    }

    // Trechos da PRF: se a lista nova falhou ou veio muito menor, mantém a
    // última lista boa (publicada) e avisa por e-mail (alerta).
    const file = getStorage().bucket().file("public/radares.json.gz");
    let previousPrf = null;
    try {
      const [buf] = await file.download();
      previousPrf = JSON.parse(zlib.gunzipSync(buf).toString()).prf || null;
    } catch (e) {
      console.log(`Sem arquivo anterior de radares: ${e.message}`);
    }
    const prevCount = previousPrf ? previousPrf.stretches.length : 0;
    const newCount = data.prf ? data.prf.stretches.length : 0;
    if (newCount < prevCount * 0.5) {
      alerta(`PRF: lista nova indisponível ou incompleta (${newCount} trechos, antes ${prevCount}). ` +
        `Mantida a lista anterior "${previousPrf?.label}". Confira a página da PRF.`);
      data.prf = previousPrf;
    }
    const today = new Date().toISOString().slice(0, 10);
    if (data.prf?.validTo && data.prf.validTo < today) {
      alerta(`PRF: a lista "${data.prf.label}" venceu em ${data.prf.validTo} e não há lista nova na página.`);
    }

    const gz = zlib.gzipSync(JSON.stringify(data), { level: 9 });
    const version = Date.now();
    await file.save(gz, {
      contentType: "application/octet-stream",
      resumable: false,
      metadata: { cacheControl: "no-cache" },
    });
    await db.doc("meta/radars").set({
      version,
      builtAt: data.builtAt,
      radars: data.radars.length,
      prfStretches: data.prf ? data.prf.stretches.length : 0,
      prfLabel: data.prf ? data.prf.label : null,
      bytes: gz.length,
    });
    console.log(`Radares publicados: versão ${version}, ${gz.length} bytes`);
  }
);

/**
 * Toda segunda: limites de velocidade por estado (para o velocímetro).
 * Só refaz os estados que mudaram; o app baixa apenas o estado onde está.
 */
exports.updateSpeedLimits = onSchedule(
  {
    schedule: "every monday 05:30",
    timeZone: "America/Sao_Paulo",
    region,
    memory: "2GiB",
    timeoutSeconds: 1800,
  },
  async () => {
    const metaRef = db.doc("meta/limits");
    const previous = (await metaRef.get()).data() || {};
    const bucket = getStorage().bucket();
    const { ufs, changed } = await buildSpeedLimits({
      previous,
      save: (uf, gz) =>
        bucket.file(`public/limites/${uf}.json.gz`).save(gz, {
          contentType: "application/octet-stream",
          resumable: false,
          metadata: { cacheControl: "no-cache" },
        }),
      log: (m) => console.log(m),
    });
    await metaRef.set({ ufs, builtAt: new Date().toISOString() });
    console.log(`Limites: ${changed} estados atualizados`);
  }
);

/**
 * Todo dia: lombadas e postos policiais rodoviários (OpenStreetMap), por
 * estado. Atualiza os estados mais antigos até acabar o tempo; em uma
 * semana passa por todos. O app baixa só o estado onde está.
 */
exports.updatePois = onSchedule(
  {
    schedule: "every day 04:10",
    timeZone: "America/Sao_Paulo",
    region,
    memory: "1GiB",
    timeoutSeconds: 1800,
  },
  async () => {
    const metaRef = db.doc("meta/pois");
    const previous = (await metaRef.get()).data() || {};
    const bucket = getStorage().bucket();
    const { ufs, changed } = await buildPois({
      previous,
      budgetMs: 1500000, // 25 min: dá para o Brasil todo numa execução
      save: (uf, gz) =>
        bucket.file(`public/pois/${uf}.json.gz`).save(gz, {
          contentType: "application/octet-stream",
          resumable: false,
          metadata: { cacheControl: "no-cache" },
        }),
    });
    await metaRef.set({ ufs, builtAt: new Date().toISOString() });
    console.log(`POIs: ${changed} estados atualizados`);
  }
);

/**
 * Limpeza diária conforme a Política de Privacidade:
 * - expedições sem atividade há 30 dias (com paradas e SOS); o histórico
 *   de cada piloto fica no próprio celular (\"Minhas viagens\");
 * - registros de avisos do clube com mais de 180 dias.
 * Alertas de perigo são apagados pela política TTL do Firestore.
 */
exports.cleanup = onSchedule(
  { schedule: "every day 04:00", timeZone: "America/Sao_Paulo", region },
  async () => {
    const day = 24 * 60 * 60 * 1000;
    const expCutoff = Timestamp.fromMillis(Date.now() - 30 * day);
    const oldExps = await db.collection("expeditions")
      .where("createdAt", "<", expCutoff).limit(200).get();
    for (const e of oldExps.docs) {
      const active = await e.ref.collection("members")
        .where("updatedAt", ">=", expCutoff).limit(1).get();
      if (active.empty) await db.recursiveDelete(e.ref);
    }

    const notifCutoff = Timestamp.fromMillis(Date.now() - 180 * day);
    const oldNotifs = await db.collectionGroup("notifications")
      .where("createdAt", "<", notifCutoff).limit(500).get();
    await Promise.all(oldNotifs.docs.map((d) => d.ref.delete()));
  }
);
