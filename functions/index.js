/**
 * Cloud Functions do UauGo (rodam no servidor do Firebase, região
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
 * - updateRadars ............. radares e trechos da PRF (todo dia; publica só se mudou)
 * - updateSpeedLimits ........ limites de velocidade por estado (segunda)
 * - updatePois ............... lombadas, postos e pedágios (todo dia)
 * - cleanup .................. limpeza diária (expedições paradas etc.)
 *
 * Os dados públicos vão para o Storage (public/...) e a versão de cada
 * arquivo para meta/{radars,limits,pois}: o app só baixa quando muda.
 */

const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError, onRequest: onHttpRequest } = require("firebase-functions/v2/https");
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
const { buildTolls, boothsFromPois } = require("./tolls");
const maps = require("./maps");
const clubs = require("./clubs");
const gold = require("./gold");

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
 * para a HelpAITech (política "UauGo - rotina com problema"; veja
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

// Pedidos ao grupo (mesmos nomes de lib/logic/group_requests.dart).
const REQUESTS = {
  fuel: ["⛽", "precisa abastecer"],
  restroom: ["🚻", "pediu parada para banheiro"],
  rest: ["☕", "precisa descansar"],
  problem: ["🔧", "está com problema no veículo"],
  behind: ["🐢", "ficou para trás. Esperem!"],
};

// Um piloto saiu para buscar um colega: só o capitão recebe.
async function avisarCapitao(code, r) {
  const exp = (await db.doc(`expeditions/${code}`).get()).data();
  const captain = exp?.captainId || exp?.leaderId;
  if (!captain || captain === r.uid) return;
  const token = (await db.doc(`users/${captain}`).get()).data()?.fcmToken;
  if (!token) return;
  const who = (r.name || "Um piloto").toString().slice(0, 60);
  const target = (r.target || "um colega").toString().slice(0, 60);
  await sendPush({
    token,
    notification: { title: `🧭 ${who} está indo até ${target}`, body: "Rota própria, a do grupo não mudou" },
    data: { type: "helping", code, uid: r.uid || "" },
  });
}

// Avisa o grupo de um pedido ("Ricardo precisa abastecer").
exports.onRequest = onDocumentCreated(
  { document: "expeditions/{code}/requests/{reqId}", region },
  async (event) => {
    const r = event.data?.data();
    if (r?.kind === "helping") return avisarCapitao(event.params.code, r);
    const k = r && REQUESTS[r.kind];
    if (!k) return;
    const who = (r.name || "Um piloto").toString().slice(0, 60);
    await sendPush({
      topic: `exp_${event.params.code}`,
      notification: { title: `${k[0]} ${who} ${k[1]}`, body: "Pedido ao grupo" },
      data: { type: "request", code: event.params.code, uid: r.uid || "" },
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

/**
 * Trocou de conta no meio da expedição (ex.: entrou em outra conta): leva
 * para a conta nova a liderança, a capitania, o posto de ferrolho e a
 * posição na lista de pilotos. Prova de que a conta antiga é da mesma
 * pessoa: o token dela, pego no aparelho ANTES da troca (vale 1 hora).
 * { oldToken } -> { codes: [códigos transferidos] }
 */
exports.transferExpeditionRoles = onCall(callOpts, async (req) => {
  const uid = accountUid(req);
  const token = req.data?.oldToken;
  if (typeof token !== "string" || token.length > 4096) {
    throw new HttpsError("invalid-argument", "Token inválido.");
  }
  let old;
  try {
    old = await getAuth().verifyIdToken(token);
  } catch (_) {
    throw new HttpsError("permission-denied", "Não foi possível confirmar a conta anterior.");
  }
  const oldUid = old.uid;
  if (oldUid === uid || old.firebase?.sign_in_provider === "anonymous") return { codes: [] };

  const col = db.collection("expeditions");
  const found = new Map();
  for (const q of [
    col.where("leaderId", "==", oldUid),
    col.where("captainId", "==", oldUid),
    col.where("sweepers", "array-contains", oldUid),
  ]) {
    for (const d of (await q.get()).docs) found.set(d.id, d.ref);
  }
  const codes = [];
  for (const [code, ref] of found) {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const e = snap.data();
      const oldMember = await tx.get(ref.collection("members").doc(oldUid));
      const changes = {};
      if (e.leaderId === oldUid) changes.leaderId = uid;
      if (e.captainId === oldUid) changes.captainId = uid;
      if (Array.isArray(e.sweepers) && e.sweepers.includes(oldUid)) {
        changes.sweepers = e.sweepers.map((s) => (s === oldUid ? uid : s))
          .filter((s, i, a) => a.indexOf(s) === i && s !== (changes.captainId ?? e.captainId));
      }
      tx.update(ref, changes);
      if (oldMember.exists) {
        tx.set(ref.collection("members").doc(uid), oldMember.data(), { merge: true });
        tx.delete(oldMember.ref);
      }
    });
    codes.push(code);
  }
  return { codes };
});

// ===================== Rotas e lugares (chave fica no servidor) ===========
// Detalhes em maps.js. O app chama estas funções no lugar do Google direto.
exports.directions = onCall(callOpts, maps.directions);
exports.routeTraffic = onCall(callOpts, maps.routeTraffic);
exports.places = onCall(callOpts, maps.places);
// IA (Gemini): entende pedidos falados livres ("restaurante bom e barato").
const ai = require("./ai");
exports.interpret = onCall(callOpts, (req) => ai.interpret(maps.requireUser(req), req.data, maps.countUse));

// ===================== Clube =====================

// Ativar (administrador, com código de ativação da HelpAITech), convidar,
// entrar (convite de uso único) e gerenciar administradores. Ver clubs.js.
exports.createClub = onCall(callOpts, (req) => clubs.createClub(accountUid(req), req.data));
exports.createClubInvite = onCall(callOpts, (req) => clubs.createClubInvite(accountUid(req), req.data));
exports.joinClub = onCall(callOpts, (req) => clubs.joinClub(accountUid(req), req.data));
exports.setClubAdmin = onCall(callOpts, (req) => clubs.setClubAdmin(accountUid(req), req.data));
// Administração UauGo (só platformAdmins/{uid}).
exports.adminCreateClub = onCall(callOpts, (req) => clubs.adminCreateClub(accountUid(req), req.data));
exports.adminActivationCode = onCall(callOpts, (req) => clubs.adminActivationCode(accountUid(req), req.data));
exports.adminMemberInvite = onCall(callOpts, (req) => clubs.adminMemberInvite(accountUid(req), req.data));
exports.adminListClubs = onCall(callOpts, (req) => clubs.adminListClubs(accountUid(req)));

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
  // Programa Ouro: estatísticas de contribuição e a condição automática.
  await db.doc(`userStats/${uid}`).delete();
  const g = await db.doc(`gold/${uid}`).get();
  if (g.exists && g.data().auto === true) await g.ref.delete();

  await getStorage().bucket().deleteFiles({ prefix: `bikes/${uid}/` });
  await db.doc(`users/${uid}`).delete();
  await getAuth().deleteUser(uid);
  return { ok: true };
});

// ===================== Programa Ouro (Gold) =====================

/**
 * A cada alerta criado ou alterado: soma nas estatísticas de contribuição de
 * quem o criou (userStats/{uid}: criados, confirmados por outros, removidos
 * pela comunidade). Os alertas se apagam sozinhos; as estatísticas ficam
 * enquanto a conta existir (Política de Privacidade, item 3).
 */
exports.onHazardStats = onDocumentWritten(
  { document: "hazards/{id}", region },
  async (event) => {
    const before = event.data?.before?.exists ? event.data.before.data() : null;
    const after = event.data?.after?.exists ? event.data.after.data() : null;
    if (!after) return; // apagado pelo TTL: nada a somar
    const d = gold.statsDelta(before, after);
    if (!d.uid || (!d.created && !d.confirmed && !d.removed)) return;
    await db.doc(`userStats/${d.uid}`).set({
      created: FieldValue.increment(d.created),
      confirmed: FieldValue.increment(d.confirmed),
      removed: FieldValue.increment(d.removed),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });

/**
 * Todo dia: concede o Ouro a quem cumpre os critérios (Termos de Uso, item
 * 7: conta com 30 dias, 15 alertas confirmados por outros, até 1 em cada 10
 * removidos) e retira de quem deixou de cumprir. Só mexe no Ouro automático
 * (gold/{uid}.auto = true); o marcado à mão pelo responsável fica.
 */
exports.updateGold = onSchedule(
  { schedule: "every day 03:30", timeZone: "America/Sao_Paulo", region, timeoutSeconds: 540 },
  async () => {
    const stats = await db.collection("userStats").get();
    let given = 0, taken = 0;
    for (const doc of stats.docs) {
      const uid = doc.id;
      let created = 0;
      try {
        created = Date.parse((await getAuth().getUser(uid)).metadata.creationTime) || 0;
      } catch (_) {
        continue; // conta não existe mais
      }
      const ok = gold.isEligible(doc.data(), created);
      const ref = db.doc(`gold/${uid}`);
      const cur = await ref.get();
      if (ok && !cur.exists) {
        await ref.set({ auto: true, since: FieldValue.serverTimestamp() });
        given++;
      } else if (!ok && cur.exists && cur.data().auto === true) {
        await ref.delete();
        taken++;
      }
    }
    console.log(`Ouro: ${given} novos, ${taken} retirados, ${stats.size} avaliados`);
  });

// ===================== Radares =====================

/**
 * Todo dia: monta o arquivo de radares (fixos do Brasil +
 * trechos de radar portátil da PRF) e publica em public/radares.json.gz.
 * O app confere a versão em meta/radars (1 leitura) e só baixa se mudou.
 * Também pode ser rodada na hora pelo Cloud Scheduler ("Forçar execução").
 */
exports.updateRadars = onSchedule(
  {
    schedule: "every day 05:00",
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

    // Só publica se o conteúdo mudou: o app baixa de novo a cada versão nova
    // (~0,5 MB), e a lista costuma ficar igual de um dia para o outro.
    const { builtAt, ...content } = data;
    const hash = require("crypto").createHash("sha256")
      .update(JSON.stringify(content)).digest("hex").slice(0, 16);
    const prevMeta = (await db.doc("meta/radars").get()).data() || {};
    if (prevMeta.hash === hash) {
      console.log("Radares sem mudança; nada publicado");
      return;
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
      hash,
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
 * Todo dia: postos policiais rodoviários, pedágios, lombadas e semáforos
 * (OpenStreetMap), por estado. Atualiza os estados mais antigos até acabar o tempo; em uma
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
      save: (folder, uf, gz) =>
        bucket.file(`public/${folder}/${uf}.json.gz`).save(gz, {
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
 * Todo dia 5: praças de pedágio com preço (custo da viagem). Praças do
 * OpenStreetMap (arquivos de updatePois) + preço e regra da moto das
 * rodovias federais (dados abertos da ANTT). Detalhes em tolls.js.
 */
exports.updateTolls = onSchedule(
  {
    schedule: "5 of month 06:00",
    timeZone: "America/Sao_Paulo",
    region,
    memory: "1GiB",
    timeoutSeconds: 900,
  },
  async () => {
    const bucket = getStorage().bucket();
    const ufs = Object.keys((await db.doc("meta/pois").get()).data()?.ufs || {});
    const booths = [];
    for (const uf of ufs) {
      try {
        const [buf] = await bucket.file(`public/pois/${uf}.json.gz`).download();
        const json = JSON.parse(zlib.gunzipSync(buf).toString());
        booths.push(...boothsFromPois(json.d || json));
      } catch (e) {
        console.log(`Pedágios: sem POIs de ${uf} (${e.message})`);
      }
    }
    const data = await buildTolls({ booths, log: (m) => console.log(m) });
    // Preços achados pela rotina semanal (n8n) nas praças sem preço da ANTT.
    const extra = await applyTollPrices(data);
    console.log(`Pedágios: ${extra} praças com preço da rotina semanal`);
    if (data.priced < 50) {
      alerta(`Pedágios: só ${data.priced} praças com preço da ANTT; mantida a versão anterior.`);
      return;
    }
    const gz = zlib.gzipSync(JSON.stringify(data), { level: 9 });
    await bucket.file("public/pedagios.json.gz").save(gz, {
      contentType: "application/octet-stream",
      resumable: false,
      metadata: { cacheControl: "no-cache" },
    });
    const version = Date.now();
    await db.doc("meta/tolls").set({
      version, builtAt: data.builtAt, month: data.month,
      plazas: data.p.length, priced: data.priced, bytes: gz.length,
    });
    console.log(`Pedágios publicados: ${data.p.length} praças, ${gz.length} bytes`);
  }
);

// ===================== Preços de pedágio (rotina semanal no n8n) ==========

/**
 * Valor de pedágio informado (ou confirmado) por um piloto no app:
 * tollReports/{chave}/reports/{uid} = { car, moto, at }. Quando 2 pilotos
 * diferentes informam valores parecidos (carro até 5% ou R$ 0,30 de
 * diferença; moto igual, contando isenta = 0), o valor vira o da praça
 * (tollPrices, method "usuarios") e a tabela do app é republicada. Praças
 * com preço oficial da ANTT não aceitam relato.
 */
exports.onTollReport = onDocumentWritten(
  { document: "tollReports/{key}/reports/{uid}", region },
  async (event) => {
    const key = event.params.key;
    const since = Date.now() - 180 * 24 * 3600 * 1000;
    const snap = await db.collection(`tollReports/${key}/reports`).get();
    const reps = snap.docs
      .map((d) => ({ uid: d.id, ...d.data() }))
      .filter((r) => (r.at?.toMillis?.() || 0) > since)
      .sort((a, b) => (b.at?.toMillis?.() || 0) - (a.at?.toMillis?.() || 0));
    const near = (a, b) => a != null && b != null && Math.abs(a - b) <= Math.max(0.3, 0.05 * Math.max(a, b));
    // O relato mais recente que tem outro piloto concordando.
    const agree = (field) => {
      for (const r of reps) {
        if (r[field] == null) continue;
        const group = reps.filter((o) => o[field] != null && near(o[field], r[field]));
        if (new Set(group.map((o) => o.uid)).size >= 2) {
          return Math.round((group.reduce((a, o) => a + o[field], 0) / group.length) * 10) / 10;
        }
      }
      return undefined;
    };
    let car = agree("car");
    let moto = agree("moto");
    // Administração do UauGo: o valor informado vale para todos na hora.
    const mine = event.data?.after?.data();
    const isAdmin = mine && (await db.doc(`platformAdmins/${event.params.uid}`).get()).exists;
    if (isAdmin) {
      if (mine.car != null) car = mine.car;
      if (mine.moto != null) moto = mine.moto;
    }
    if (car === undefined && moto === undefined) return;
    const data = await readTollTable();
    const row = data.p.find((r) => plazaKey(r) === key.replace(/_/g, "/"));
    if (!row) return;
    const ref = db.doc(`tollPrices/${key}`);
    const cur = (await ref.get()).data();
    // Praça com preço oficial (ANTT) também pode ser corrigida (o valor
    // publicado às vezes está defasado); vale com 2 pilotos ou a administração.
    const newCar = car ?? cur?.car ?? row[2] ?? null;
    if (!(newCar > 0)) return;
    await ref.set({
      car: newCar,
      moto: moto !== undefined ? moto : (cur?.moto ?? null),
      found: true,
      method: isAdmin ? "admin" : "usuarios",
      estimated: false,
      name: cur?.name || "",
      source: isAdmin ? "Informado pela administração do UauGo" : "Confirmado por pilotos no UauGo",
      checkedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    await applyTollPrices(data);
    await writeTollTable(data);
    console.log(`Pedágio ${key}: confirmado por usuários (carro ${newCar}, moto ${moto})`);
  }
);

/** Chave da praça: posição do 1º ponto com 5 casas ("-22.12345,-47.12345"). */
const plazaKey = (row) => `${Number(row[0]).toFixed(5)},${Number(row[1]).toFixed(5)}`;

/**
 * Preenche as praças sem preço da ANTT com o de tollPrices/{chave} (rotina
 * do n8n, planilha conferida pelo Ricardo ou confirmado pelos usuários).
 * Moto: guarda a fração do carro (como na tabela). Refaz também as já
 * preenchidas antes (o valor pode ter sido corrigido). As praças da ANTT
 * não têm tollPrices e ficam como estão.
 * data.s[chave] = "e" (estimado, a confirmar) ou "u" (confirmado por
 * usuários); data.n[chave] = nome da praça. Devolve quantas preencheu.
 */
async function applyTollPrices(data) {
  const snap = await db.collection("tollPrices").where("found", "==", true).get();
  const byKey = new Map(snap.docs.map((d) => [d.id, d.data()]));
  data.s = {};
  data.n = {};
  let n = 0;
  for (const row of data.p) {
    const key = plazaKey(row);
    const t = byKey.get(key);
    if (!t || !(t.car > 0)) continue;
    row[2] = Math.round(t.car * 100) / 100;
    row[3] = t.moto === 0 ? 0 : (t.moto > 0 ? Math.round((t.moto / t.car) * 100) / 100 : null);
    data.s[key] = t.method === "usuarios" || t.method === "admin" ? "u" : "e";
    if (t.name) data.n[key] = String(t.name).slice(0, 60);
    n++;
  }
  return n;
}

/** Lê a tabela publicada (public/pedagios.json.gz). */
async function readTollTable() {
  const [buf] = await getStorage().bucket().file("public/pedagios.json.gz").download();
  return JSON.parse(zlib.gunzipSync(buf).toString());
}

/** Publica a tabela e avisa os apps (meta/tolls.version). */
async function writeTollTable(data) {
  const gz = zlib.gzipSync(JSON.stringify(data), { level: 9 });
  await getStorage().bucket().file("public/pedagios.json.gz").save(gz, {
    contentType: "application/octet-stream",
    resumable: false,
    metadata: { cacheControl: "no-cache" },
  });
  await db.doc("meta/tolls").set({
    version: Date.now(), builtAt: data.builtAt, month: data.month,
    plazas: data.p.length, priced: data.priced, bytes: gz.length,
  }, { merge: true });
}

/**
 * Rotina semanal de preços de pedágio (fluxo do n8n na VPS). Protegida pela
 * senha TOLL_INGEST_SECRET (cabeçalho x-uaugo-key); o n8n não acessa o banco.
 * - GET ?limit=40: praças sem preço ainda não conferidas nos últimos 30 dias.
 * - POST { items: [{ key, name, car, moto, source }] }: grava em
 *   tollPrices/{key} (preço estimado, com fonte e data) e atualiza a tabela
 *   do app na hora. car/moto em R$ (moto 0 = isenta; null = não achou).
 */
exports.tollPrices = onHttpRequest({ region, invoker: "public", timeoutSeconds: 300, memory: "512MiB" }, async (req, res) => {
  const secret = process.env.TOLL_INGEST_SECRET || "";
  const got = String(req.get("x-uaugo-key") || "");
  const ok = secret.length > 20 && got.length === secret.length &&
    require("crypto").timingSafeEqual(Buffer.from(got), Buffer.from(secret));
  if (!ok) {
    res.status(401).json({ error: "não autorizado" });
    return;
  }
  try {
    const data = await readTollTable();
    if (req.method === "GET") {
      const limit = Math.min(Math.max(Number(req.query.limit) || 40, 1), 150);
      const since = Date.now() - 30 * 24 * 3600 * 1000;
      const seen = await db.collection("tollPrices")
        .where("checkedAt", ">", Timestamp.fromMillis(since)).get();
      const recent = new Set(seen.docs.map((d) => d.id));
      // Ordem pedida: SP, MG, RJ, PR, SC, RS e depois os demais estados. O
      // estado vem dos arquivos de pontos (cada praça saiu de uma cabine de
      // um estado); dentro do estado, a mais perto de São Paulo primeiro.
      const ORDER = ["SP", "MG", "RJ", "PR", "SC", "RS"];
      const bucket = getStorage().bucket();
      const byUf = [];
      for (const uf of ORDER) {
        try {
          const [buf] = await bucket.file(`public/pois/${uf}.json.gz`).download();
          const json = JSON.parse(zlib.gunzipSync(buf).toString());
          byUf.push(boothsFromPois(json.d || json));
        } catch (_) {
          byUf.push([]);
        }
      }
      const rank = (r) => {
        const la = Number(r[0]), lo = Number(r[1]);
        for (let i = 0; i < byUf.length; i++) {
          if (byUf[i].some((b) => Math.abs(b[0] - la) < 0.01 && Math.abs(b[1] - lo) < 0.01)) return i;
        }
        return ORDER.length;
      };
      const d2 = (r) => (Number(r[0]) + 23.55) ** 2 + (Number(r[1]) + 46.63) ** 2;
      const missing = data.p
        .filter((r) => r[2] == null && !recent.has(plazaKey(r)))
        .map((r) => ({ r, k: rank(r), d: d2(r) }))
        .sort((a, b) => a.k - b.k || a.d - b.d)
        .map((x) => x.r)
        .slice(0, limit)
        .map((r) => ({ key: plazaKey(r), lat: Number(r[0]), lng: Number(r[1]) }));
      const total = data.p.filter((r) => r[2] == null).length;
      res.json({ missing, totalWithoutPrice: total, plazas: data.p.length });
      return;
    }
    if (req.method !== "POST") {
      res.status(405).end();
      return;
    }
    const items = Array.isArray(req.body?.items) ? req.body.items.slice(0, 150) : [];
    const keys = new Set(data.p.map(plazaKey));
    const num = (v) => (typeof v === "number" && isFinite(v) && v >= 0 && v < 500 ? Math.round(v * 100) / 100 : null);
    const batch = db.batch();
    let saved = 0;
    // Valores da planilha conferida ou confirmados pelos usuários não são
    // trocados pela rotina automática.
    const locked = new Set((await db.collection("tollPrices")
      .where("method", "in", ["planilha", "usuarios", "admin"]).get()).docs.map((d) => d.id));
    for (const it of items) {
      const key = String(it?.key || "");
      if (!keys.has(key) || locked.has(key.replace(/\//g, "_"))) continue;
      const car = num(it.car);
      const moto = num(it.moto);
      batch.set(db.doc(`tollPrices/${key.replace(/\//g, "_")}`), {
        car, moto,
        found: car != null && car > 0,
        name: String(it.name || "").slice(0, 120),
        source: String(it.source || "").slice(0, 300),
        method: "n8n-ia",
        estimated: true,
        checkedAt: FieldValue.serverTimestamp(),
      });
      saved++;
    }
    await batch.commit();
    const patched = await applyTollPrices(data);
    await writeTollTable(data);
    console.log(`Pedágios (rotina): ${saved} recebidos, ${patched} praças com preço da rotina`);
    res.json({ saved, patched });
  } catch (e) {
    console.error("tollPrices", e);
    res.status(500).json({ error: "falha ao processar" });
  }
});

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
