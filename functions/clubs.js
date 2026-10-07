/**
 * Clube oficial: criação e entrada controladas pelo SERVIDOR.
 *
 * - Criar clube: só o PRESIDENTE, com um CÓDIGO DE ATIVAÇÃO fornecido pela
 *   HelpAITech (clubActivations/{código}, gerado por
 *   scripts/gerar-codigos-clube.js). Cada código cria um único clube.
 * - Entrar no clube: só com um CONVITE de uso único gerado pelo presidente
 *   no app (clubInvites/{código}, vale 7 dias e uma entrada).
 * - As coleções clubActivations e clubInvites não são acessíveis pelo app
 *   (firestore.rules): tudo passa por estas funções.
 * - Tentativas erradas de código são limitadas por dia (usage/{uid}),
 *   para ninguém tentar adivinhar.
 *
 * Funções (chamadas pelo app com httpsCallable):
 * - createClub:       { activationCode, name, memberName, city?, bike? } -> { clubId, name }
 * - createClubInvite: { clubId } -> { code, expiresAt }
 * - joinClub:         { inviteCode, memberName, city?, bike? } -> { clubId, name }
 */

const { HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const crypto = require("crypto");

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // sem letras que confundem
const INVITE_DAYS = 7;
const MAX_TRIES_PER_DAY = 20; // códigos errados (ativação + convite)
const MAX_INVITES_PER_DAY = 50; // por presidente

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

/** Conta uma tentativa de código errado; recusa depois do limite do dia. */
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

async function checkTries(uid) {
  const d = (await getFirestore().doc(`usage/${uid}`).get()).data() || {};
  const day = new Date().toISOString().slice(0, 10);
  if (d.day === day && (d.clubTries || 0) >= MAX_TRIES_PER_DAY) {
    throw new HttpsError("resource-exhausted",
      "Muitas tentativas com código errado hoje. Tente amanhã.");
  }
}

/** Presidente usa o código de ativação para criar o clube. */
async function createClub(uid, data) {
  const db = getFirestore();
  const code = normalize(data?.activationCode);
  const name = text(data?.name, 60, true, "o nome do clube");
  const memberName = text(data?.memberName, 60, true, "seu nome de piloto");
  const city = text(data?.city, 80, false);
  const bike = text(data?.bike, 100, false);
  await checkTries(uid);
  if (code.length !== 12) {
    await countFailedTry(uid);
    throw new HttpsError("not-found", "Código de ativação inválido.");
  }

  const actRef = db.doc(`clubActivations/${code}`);
  let clubId = randomCode(8);
  while ((await db.doc(`clubs/${clubId}`).get()).exists) clubId = randomCode(8);
  const clubRef = db.doc(`clubs/${clubId}`);

  const ok = await db.runTransaction(async (tx) => {
    const act = await tx.get(actRef);
    if (!act.exists || act.data().status !== "available") return false;
    tx.set(clubRef, {
      name,
      createdBy: uid,
      presidentId: uid,
      activationCode: code,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(clubRef.collection("members").doc(uid), {
      name: memberName, city, bike, role: "president",
      joinedAt: FieldValue.serverTimestamp(),
    });
    tx.update(actRef, {
      status: "used", usedBy: uid, clubId, clubName: name,
      usedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!ok) {
    await countFailedTry(uid);
    throw new HttpsError("not-found", "Código de ativação inválido ou já utilizado.");
  }
  return { clubId, name };
}

/** O presidente gera um convite de uso único para um novo membro. */
async function createClubInvite(uid, data) {
  const db = getFirestore();
  const clubId = normalize(data?.clubId);
  const club = await db.doc(`clubs/${clubId}`).get();
  const president = club.exists && (club.data().presidentId || club.data().createdBy);
  if (!club.exists || president !== uid) {
    throw new HttpsError("permission-denied", "Só o presidente do clube gera convites.");
  }
  // Limite diário de convites por presidente.
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
  const memberName = text(data?.memberName, 60, true, "seu nome de piloto");
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
    if (i.usedBy) return { error: "Este convite já foi usado. Peça um novo ao presidente." };
    if (i.expiresAt.toMillis() < Date.now()) return { error: "Convite vencido. Peça um novo ao presidente." };
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

module.exports = { createClub, createClubInvite, joinClub, normalize, randomCode, ALPHABET };
