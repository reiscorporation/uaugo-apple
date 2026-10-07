// Testes do clube oficial (functions/clubs.js) no emulador do Firestore.
// Rodar na raiz do projeto:
//   firebase emulators:exec --only firestore --project demo-comboio "node --test functions/test/clubs.test.js"
const test = require("node:test");
const assert = require("node:assert");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

initializeApp({ projectId: "demo-comboio" });
const db = getFirestore();
const clubs = require("../clubs");

const ACT = "ABCDEFGH2345";
const rejects = (p, re) => assert.rejects(p, (e) => re.test(e.message));

test.beforeEach(async () => {
  for (const c of ["clubActivations", "clubInvites", "clubs", "usage"]) {
    await db.recursiveDelete(db.collection(c));
  }
  await db.doc(`clubActivations/${ACT}`).set({ status: "available", note: "teste" });
});

test("presidente cria o clube com o código de ativação (aceita com traços)", async () => {
  const r = await clubs.createClub("pres", {
    activationCode: "abcd-efgh-2345", name: "Lobos", memberName: "João",
  });
  const club = (await db.doc(`clubs/${r.clubId}`).get()).data();
  assert.strictEqual(club.presidentId, "pres");
  const m = (await db.doc(`clubs/${r.clubId}/members/pres`).get()).data();
  assert.strictEqual(m.role, "president");
  assert.strictEqual((await db.doc(`clubActivations/${ACT}`).get()).data().status, "used");
});

test("código de ativação não vale duas vezes", async () => {
  await clubs.createClub("pres", { activationCode: ACT, name: "Lobos", memberName: "João" });
  await rejects(clubs.createClub("outro", { activationCode: ACT, name: "X", memberName: "Y" }),
    /inválido ou já utilizado/);
});

test("código de ativação inventado é recusado", () =>
  rejects(clubs.createClub("pres", { activationCode: "ZZZZZZZZZZZZ", name: "X", memberName: "Y" }),
    /inválido/));

test("só o presidente gera convite", async () => {
  const { clubId } = await clubs.createClub("pres", { activationCode: ACT, name: "Lobos", memberName: "João" });
  await rejects(clubs.createClubInvite("intruso", { clubId }), /Só o presidente/);
});

test("convite de uso único: entra uma pessoa, a segunda é recusada", async () => {
  const { clubId } = await clubs.createClub("pres", { activationCode: ACT, name: "Lobos", memberName: "João" });
  const { code } = await clubs.createClubInvite("pres", { clubId });
  assert.match(code, /^[A-Z0-9]{8}$/);
  const r = await clubs.joinClub("m1", { inviteCode: `${code.slice(0, 4)}-${code.slice(4)}`, memberName: "Ana" });
  assert.strictEqual(r.clubId, clubId);
  const m = (await db.doc(`clubs/${clubId}/members/m1`).get()).data();
  assert.strictEqual(m.role, "member");
  assert.strictEqual(m.invitedBy, "pres");
  await rejects(clubs.joinClub("m2", { inviteCode: code, memberName: "Bia" }), /já foi usado/);
});

test("convite vencido é recusado", async () => {
  const { clubId } = await clubs.createClub("pres", { activationCode: ACT, name: "Lobos", memberName: "João" });
  const { code } = await clubs.createClubInvite("pres", { clubId });
  await db.doc(`clubInvites/${code}`).update({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
  await rejects(clubs.joinClub("m1", { inviteCode: code, memberName: "Ana" }), /vencido/);
});

test("muitas tentativas erradas bloqueiam no dia", async () => {
  for (let i = 0; i < 20; i++) {
    await rejects(clubs.joinClub("chute", { inviteCode: "AAAA2222", memberName: "X" }), /inválido/);
  }
  await rejects(clubs.joinClub("chute", { inviteCode: "AAAA2222", memberName: "X" }), /Muitas tentativas/);
});
