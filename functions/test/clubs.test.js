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

const NEW = "ABCDEFGH2345"; // código sem clube: cria um clube novo
const ADM1 = "BBBBCCCC2345"; // códigos do clube pré-cadastrado LOBOS123
const ADM2 = "DDDDEEEE2345";
const rejects = (p, re) => assert.rejects(p, (e) => re.test(e.message));
const member = async (club, uid) => (await db.doc(`clubs/${club}/members/${uid}`).get()).data();
const club = async (id) => (await db.doc(`clubs/${id}`).get()).data();

test.beforeEach(async () => {
  for (const c of ["clubActivations", "clubInvites", "clubs", "usage", "platformAdmins"]) {
    await db.recursiveDelete(db.collection(c));
  }
  await db.doc("clubs/LOBOS123").set({ name: "Lobos da Estrada", status: "reserved", admins: [] });
  await db.doc(`clubActivations/${NEW}`).set({ status: "available", note: "novo" });
  await db.doc(`clubActivations/${ADM1}`).set({ status: "available", clubId: "LOBOS123" });
  await db.doc(`clubActivations/${ADM2}`).set({ status: "available", clubId: "LOBOS123" });
});

test("código vinculado: vira administrador do clube pré-cadastrado (nome do cadastro)", async () => {
  const r = await clubs.createClub("a1", { activationCode: "bbbb-cccc-2345", memberName: "João", name: "outro nome" });
  assert.deepStrictEqual(r, { clubId: "LOBOS123", name: "Lobos da Estrada" });
  const c = await club("LOBOS123");
  assert.deepStrictEqual(c.admins, ["a1"]);
  assert.strictEqual(c.status, "active");
  assert.strictEqual((await member("LOBOS123", "a1")).role, "admin");
});

test("um clube pode ter vários administradores (um código para cada)", async () => {
  await clubs.createClub("a1", { activationCode: ADM1, memberName: "João" });
  await clubs.createClub("a2", { activationCode: ADM2, memberName: "Maria" });
  assert.deepStrictEqual((await club("LOBOS123")).admins.sort(), ["a1", "a2"]);
});

test("código sem clube cria um clube novo e exige o nome", async () => {
  await rejects(clubs.createClub("p", { activationCode: NEW, memberName: "Zé" }), /nome do clube/);
  const r = await clubs.createClub("p", { activationCode: NEW, memberName: "Zé", name: "Jipeiros do Vale" });
  assert.strictEqual((await club(r.clubId)).name, "Jipeiros do Vale");
  assert.deepStrictEqual((await club(r.clubId)).admins, ["p"]);
});

test("código de ativação não vale duas vezes", async () => {
  await clubs.createClub("a1", { activationCode: ADM1, memberName: "João" });
  await rejects(clubs.createClub("x", { activationCode: ADM1, memberName: "Y" }), /já utilizado/);
});

test("código de ativação inventado é recusado", () =>
  rejects(clubs.createClub("p", { activationCode: "ZZZZZZZZZZZZ", name: "X", memberName: "Y" }), /inválido/));

test("só administrador gera convite", async () => {
  await clubs.createClub("a1", { activationCode: ADM1, memberName: "João" });
  await rejects(clubs.createClubInvite("intruso", { clubId: "LOBOS123" }), /administradores/);
});

test("convite de uso único: entra uma pessoa, a segunda é recusada", async () => {
  await clubs.createClub("a1", { activationCode: ADM1, memberName: "João" });
  const { code } = await clubs.createClubInvite("a1", { clubId: "LOBOS123" });
  assert.match(code, /^[A-Z0-9]{8}$/);
  const r = await clubs.joinClub("m1", { inviteCode: `${code.slice(0, 4)}-${code.slice(4)}`, memberName: "Ana" });
  assert.strictEqual(r.clubId, "LOBOS123");
  const m = await member("LOBOS123", "m1");
  assert.strictEqual(m.role, "member");
  assert.strictEqual(m.invitedBy, "a1");
  await rejects(clubs.joinClub("m2", { inviteCode: code, memberName: "Bia" }), /já foi usado/);
});

test("convite vencido é recusado", async () => {
  await clubs.createClub("a1", { activationCode: ADM1, memberName: "João" });
  const { code } = await clubs.createClubInvite("a1", { clubId: "LOBOS123" });
  await db.doc(`clubInvites/${code}`).update({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
  await rejects(clubs.joinClub("m1", { inviteCode: code, memberName: "Ana" }), /vencido/);
});

test("administrador promove e rebaixa; o clube nunca fica sem administrador", async () => {
  await clubs.createClub("a1", { activationCode: ADM1, memberName: "João" });
  const { code } = await clubs.createClubInvite("a1", { clubId: "LOBOS123" });
  await clubs.joinClub("m1", { inviteCode: code, memberName: "Ana" });
  await rejects(clubs.setClubAdmin("m1", { clubId: "LOBOS123", uid: "m1", admin: true }), /administradores/);
  await rejects(clubs.setClubAdmin("a1", { clubId: "LOBOS123", uid: "a1", admin: false }), /pelo menos um/);
  await clubs.setClubAdmin("a1", { clubId: "LOBOS123", uid: "m1", admin: true });
  assert.strictEqual((await member("LOBOS123", "m1")).role, "admin");
  await clubs.setClubAdmin("m1", { clubId: "LOBOS123", uid: "a1", admin: false });
  assert.deepStrictEqual((await club("LOBOS123")).admins, ["m1"]);
  assert.strictEqual((await member("LOBOS123", "a1")).role, "member");
});

test("muitas tentativas erradas bloqueiam no dia", async () => {
  for (let i = 0; i < 20; i++) {
    await rejects(clubs.joinClub("chute", { inviteCode: "AAAA2222", memberName: "X" }), /inválido/);
  }
  await rejects(clubs.joinClub("chute", { inviteCode: "AAAA2222", memberName: "X" }), /Muitas tentativas/);
});

test("administração UauGo: só quem é administrador da plataforma", async () => {
  await rejects(clubs.adminCreateClub("zé", { name: "Clube X" }), /administração do UauGo/);
  await rejects(clubs.adminListClubs("zé"), /administração do UauGo/);
});

test("administração UauGo: cadastra clube, gera código de administrador e convite", async () => {
  await db.doc("platformAdmins/ric").set({ email: "r@x.com" });
  const { clubId, name } = await clubs.adminCreateClub("ric", { name: "Águias do Asfalto", uf: "sp" });
  assert.strictEqual(name, "Águias do Asfalto");
  assert.strictEqual((await club(clubId)).status, "reserved");
  assert.strictEqual((await club(clubId)).uf, "SP");

  // Código de administrador: o presidente ativa e vira administrador.
  const act = await clubs.adminActivationCode("ric", { clubId, note: "presidente" });
  assert.strictEqual(act.code.length, 12);
  assert.strictEqual(act.clubName, "Águias do Asfalto");
  await clubs.createClub("pres", { activationCode: act.code, memberName: "Presidente" });
  assert.deepStrictEqual((await club(clubId)).admins, ["pres"]);

  // Convite de membro direto (sem ser administrador do clube).
  const inv = await clubs.adminMemberInvite("ric", { clubId });
  assert.strictEqual(inv.code.length, 8);
  await clubs.joinClub("m9", { inviteCode: inv.code, memberName: "Membro" });
  assert.strictEqual((await member(clubId, "m9")).role, "member");

  const { clubs: list } = await clubs.adminListClubs("ric");
  const mine = list.find((c) => c.id === clubId);
  assert.deepStrictEqual([mine.admins, mine.members], [1, 2]);
});
