/**
 * Clube oficial: criação, administradores e entrada controlados pelo SERVIDOR.
 *
 * - Clubes podem ser PRÉ-CADASTRADOS pela HelpAITech (scripts/criar-clubes.js):
 *   ficam invisíveis no app até terem administradores.
 * - ADMINISTRADORES: quem usa um CÓDIGO DE ATIVAÇÃO fornecido pela HelpAITech
 *   (clubActivations/{código}, scripts/gerar-codigos-clube.js) vira
 *   administrador do clube daquele código. Um clube pode ter vários
 *   administradores (um código para cada). Código sem clube vinculado cria
 *   um clube novo com o nome informado.
 * - Administradores geram CONVITES de uso único (clubInvites/{código}, 7 dias),
 *   removem membros e promovem/rebaixam outros administradores (o clube
 *   nunca fica sem nenhum).
 * - clubActivations e clubInvites não são acessíveis pelo app
 *   (firestore.rules): tudo passa por estas funções.
 * - Tentativas erradas de código são limitadas por dia (usage/{uid}).
 *
 * Funções (chamadas pelo app com httpsCallable):
 * - createClub:       { activationCode, name?, memberName, city?, bike? } -> { clubId, name }
 * - createClubInvite: { clubId } -> { code, expiresAt }
 * - joinClub:         { inviteCode, memberName, city?, bike? } -> { clubId, name }
 * - setClubAdmin:     { clubId, uid, admin: true|false } -> { ok }
 */

const { HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const crypto = require("crypto");

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // sem letras que confundem
const INVITE_DAYS = 7;
const MAX_TRIES_PER_DAY = 20; // códigos errados (ativação + convite)
const MAX_INVITES_PER_DAY = 50; // por administrador

/** Código aleatório seguro com [n] caracteres do ALPHABET. */
function randomCode(n) {
  const bytes = crypto.randomBytes(n);
  return Array.from(bytes, (b) => ALPHABET[b % ALPHABET.length]).join("");
}

/** "abcd-efgh 1234" -> "ABCDEFGH1234" (o usuário pode digitar com traço). */
function normalize(code) {
  return typeof code === "string" ? code.toUpperCase().replace(/[^A-Z0-9]/g, "") : "";
}

/** Texto curto obrigatório/opcional, sem espaços sobrando. */
function text(v, max, required, label) {
  const s = typeof v === "string" ? v.trim().slice(0, max) : "";
  if (required && !s) throw new HttpsError("invalid-argument", `Informe ${label}.`);
  return s;
}

/** Administradores do clube (inclui o formato antigo, com presidentId). */
function adminsOf(club) {
  if (Array.isArray(club.admins)) return [...club.admins];
  const old = club.presidentId || club.createdBy;
  return old ? [old] : [];
}

/** Conta uma tentativa de código errado. */
async function countFailedTry(uid) {
  const db = getFirestore();
  const ref = db.doc(`usage/${uid}`);
  const day = new Date().toISOString().slice(0, 10);
  await db.runTransaction(async (tx) => {
    const d = (await tx.get(ref)).data() || {};
    const n = d.day === day ? d.clubTries || 0 : 0;
    tx.set(ref, d.day === day ? { ...d, clubTries: n + 1 } : { day, clubTries: 1 });
  });
}

/** Recusa depois de muitas tentativas erradas no mesmo dia. */
async function checkTries(uid) {
  const d = (await getFirestore().doc(`usage/${uid}`).get()).data() || {};
  const day = new Date().toISOString().slice(0, 10);
  if (d.day === day && (d.clubTries || 0) >= MAX_TRIES_PER_DAY) {
    throw new HttpsError("resource-exhausted",
      "Muitas tentativas com código errado hoje. Tente amanhã.");
  }
}

/** Confere se [uid] administra o clube; devolve os dados do clube. */
async function requireAdmin(clubId, uid) {
  const snap = await getFirestore().doc(`clubs/${clubId}`).get();
  if (!snap.exists || !adminsOf(snap.data()).includes(uid)) {
    throw new HttpsError("permission-denied", "Só os administradores do clube podem fazer isso.");
  }
  return snap.data();
}

/**
 * Usa o código de ativação: vira administrador do clube vinculado ao código
 * (clube pré-cadastrado) ou cria um clube novo com o nome informado.
 */
async function createClub(uid, data) {
  const db = getFirestore();
  const code = normalize(data?.activationCode);
  const memberName = text(data?.memberName, 60, true, "seu nome");
  const city = text(data?.city, 80, false);
  const bike = text(data?.bike, 100, false);
  const newName = text(data?.name, 60, false);
  await checkTries(uid);
  if (code.length !== 12) {
    await countFailedTry(uid);
    throw new HttpsError("not-found", "Código de ativação inválido.");
  }

  const actRef = db.doc(`clubActivations/${code}`);
  // Id para o caso de o código não ter clube vinculado (clube novo).
  let freshId = randomCode(8);
  while ((await db.doc(`clubs/${freshId}`).get()).exists) freshId = randomCode(8);

  const result = await db.runTransaction(async (tx) => {
    // 1) Leituras (o Firestore exige ler tudo antes de gravar).
    const act = await tx.get(actRef);
    if (!act.exists || act.data().status !== "available") return { error: "Código de ativação inválido ou já utilizado." };
    const a = act.data();
    const clubId = a.clubId || freshId;
    const clubRef = db.doc(`clubs/${clubId}`);
    const memberRef = db.doc(`clubs/${clubId}/members/${uid}`);
    const club = a.clubId ? await tx.get(clubRef) : null;
    const m = await tx.get(memberRef);

    // 2) Gravações.
    let name;
    if (a.clubId) {
      // Clube já cadastrado pela HelpAITech: a pessoa vira administradora.
      if (!club.exists) return { error: "O clube deste código não existe mais. Fale com a HelpAITech." };
      name = club.data().name;
      tx.update(clubRef, {
        admins: [...new Set([...adminsOf(club.data()), uid])],
        status: "active",
        activatedAt: club.data().activatedAt || FieldValue.serverTimestamp(),
      });
    } else {
      if (!newName) return { error: "Informe o nome do clube.", soft: true };
      name = newName;
      tx.set(clubRef, {
        name, admins: [uid], status: "active", createdBy: uid,
        createdAt: FieldValue.serverTimestamp(), activatedAt: FieldValue.serverTimestamp(),
      });
    }
    // Membro (ou já membro) passa a ser administrador.
    if (m.exists) {
      tx.update(memberRef, { role: "admin" });
    } else {
      tx.set(memberRef, {
        name: memberName, city, bike, role: "admin", joinedAt: FieldValue.serverTimestamp(),
      });
    }
    tx.update(actRef, {
      status: "used", usedBy: uid, clubId, clubName: name, usedAt: FieldValue.serverTimestamp(),
    });
    return { clubId, name };
  });
  if (result.error) {
    if (!result.soft) await countFailedTry(uid);
    throw new HttpsError(result.soft ? "invalid-argument" : "not-found", result.error);
  }
  return result;
}

/** Um administrador gera um convite de uso único para um novo membro. */
async function createClubInvite(uid, data) {
  const db = getFirestore();
  const clubId = normalize(data?.clubId);
  await requireAdmin(clubId, uid);
  // Limite diário de convites por administrador.
  const since = Timestamp.fromMillis(Date.now() - 24 * 3600e3);
  const today = await db.collection("clubInvites")
    .where("createdBy", "==", uid).where("createdAt", ">=", since).count().get();
  if (today.data().count >= MAX_INVITES_PER_DAY) {
    throw new HttpsError("resource-exhausted", "Limite de convites de hoje atingido.");
  }

  let code = randomCode(8);
  while ((await db.doc(`clubInvites/${code}`).get()).exists) code = randomCode(8);
  const expiresAt = Timestamp.fromMillis(Date.now() + INVITE_DAYS * 24 * 3600e3);
  await db.doc(`clubInvites/${code}`).set({
    clubId, createdBy: uid, createdAt: Timestamp.now(), expiresAt, usedBy: null,
  });
  return { code, expiresAt: expiresAt.toMillis() };
}

/** Novo membro entra com o convite (que deixa de valer na hora). */
async function joinClub(uid, data) {
  const db = getFirestore();
  const code = normalize(data?.inviteCode);
  const memberName = text(data?.memberName, 60, true, "seu nome");
  const city = text(data?.city, 80, false);
  const bike = text(data?.bike, 100, false);
  await checkTries(uid);
  if (code.length !== 8) {
    await countFailedTry(uid);
    throw new HttpsError("not-found", "Convite inválido.");
  }

  const invRef = db.doc(`clubInvites/${code}`);
  const result = await db.runTransaction(async (tx) => {
    const inv = await tx.get(invRef);
    if (!inv.exists) return { error: "Convite inválido." };
    const i = inv.data();
    if (i.usedBy) return { error: "Este convite já foi usado. Peça um novo a um administrador do clube." };
    if (i.expiresAt.toMillis() < Date.now()) return { error: "Convite vencido. Peça um novo a um administrador do clube." };
    const clubRef = db.doc(`clubs/${i.clubId}`);
    const club = await tx.get(clubRef);
    if (!club.exists) return { error: "Este clube não existe mais." };
    const memberRef = clubRef.collection("members").doc(uid);
    if ((await tx.get(memberRef)).exists) {
      return { clubId: i.clubId, name: club.data().name }; // já é membro: não gasta o convite
    }
    tx.set(memberRef, {
      name: memberName, city, bike, role: "member", invitedBy: i.createdBy,
      joinedAt: FieldValue.serverTimestamp(),
    });
    tx.update(invRef, { usedBy: uid, usedAt: FieldValue.serverTimestamp() });
    return { clubId: i.clubId, name: club.data().name };
  });
  if (result.error) {
    await countFailedTry(uid);
    throw new HttpsError("not-found", result.error);
  }
  return result;
}

/** Um administrador promove um membro a administrador, ou tira a função. */
async function setClubAdmin(uid, data) {
  const db = getFirestore();
  const clubId = normalize(data?.clubId);
  const target = typeof data?.uid === "string" ? data.uid : "";
  const makeAdmin = data?.admin === true;
  const club = await requireAdmin(clubId, uid);
  const memberRef = db.doc(`clubs/${clubId}/members/${target}`);
  if (!target || !(await memberRef.get()).exists) {
    throw new HttpsError("not-found", "Membro não encontrado.");
  }
  const admins = adminsOf(club);
  if (!makeAdmin && admins.length === 1 && admins[0] === target) {
    throw new HttpsError("failed-precondition",
      "O clube precisa de pelo menos um administrador. Promova outro membro antes.");
  }
  const next = makeAdmin ? [...new Set([...admins, target])] : admins.filter((a) => a !== target);
  const batch = db.batch();
  // Grava a lista completa (e limpa o formato antigo presidentId/createdBy).
  batch.update(db.doc(`clubs/${clubId}`), { admins: next });
  batch.update(memberRef, { role: makeAdmin ? "admin" : "member" });
  await batch.commit();
  return { ok: true };
}

module.exports = {
  createClub, createClubInvite, joinClub, setClubAdmin, adminsOf, normalize, randomCode, ALPHABET,
};
