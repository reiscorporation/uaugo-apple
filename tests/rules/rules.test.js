// Testes das regras de segurança do Firestore no emulador.
// Rodar na raiz do projeto:
//   firebase emulators:exec --only firestore --project demo-comboio "npm --prefix tests/rules test"
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs, Timestamp,
} = require("firebase/firestore");

let env;
const inHours = (h) => Timestamp.fromMillis(Date.now() + h * 3600e3);
const db = (uid) =>
  (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-comboio",
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8"),
    },
  });
});

after(async () => { if (env) await env.cleanup(); });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await setDoc(doc(f, "expeditions/ABC123"), { name: "Serra", leaderId: "alice" });
    await setDoc(doc(f, "expeditions/ABC123/members/alice"), { name: "Alice" });
    await setDoc(doc(f, "expeditions/ABC123/members/carol"), { name: "Carol" });
    await setDoc(doc(f, "clubs/CLUB01"), { name: "Clube", createdBy: "alice" });
    await setDoc(doc(f, "clubs/CLUB01/members/alice"), { name: "Alice", city: "" });
    await setDoc(doc(f, "users/alice"), { consent: { findable: true } });
    await setDoc(doc(f, "hazards/h1"), {
      type: "pothole", lat: -21, lng: -47, cell: "-210_-470", createdBy: "alice",
      confirmations: 1, dismissals: 0, expiresAt: inHours(1),
    });
  });
});

describe("Expedições", () => {
  it("sem login não lê nada", () =>
    assertFails(getDoc(doc(db(null), "expeditions/ABC123"))));
  it("com o código, abre a expedição", () =>
    assertSucceeds(getDoc(doc(db("bob"), "expeditions/ABC123"))));
  it("ninguém lista todas as expedições", () =>
    assertFails(getDocs(collection(db("alice"), "expeditions"))));
  it("membro grava a própria posição", () =>
    assertSucceeds(setDoc(doc(db("alice"), "expeditions/ABC123/members/alice"),
      { lat: -21, lng: -47 }, { merge: true })));
  it("ninguém grava a posição de outro", () =>
    assertFails(setDoc(doc(db("bob"), "expeditions/ABC123/members/alice"), { lat: 0 })));
  it("quem não é membro não vê as paradas", () =>
    assertFails(getDocs(collection(db("bob"), "expeditions/ABC123/stops"))));
  it("líder cria parada", () =>
    assertSucceeds(setDoc(doc(db("alice"), "expeditions/ABC123/stops/s1"),
      { name: "Posto", lat: 1, lng: 2, order: 1, createdBy: "alice" })));
  it("membro que não é líder não altera o roteiro", () =>
    assertFails(setDoc(doc(db("carol"), "expeditions/ABC123/stops/s2"),
      { name: "Posto", lat: 1, lng: 2, order: 1, createdBy: "carol" })));
  it("membro vê o roteiro", () =>
    assertSucceeds(getDocs(collection(db("carol"), "expeditions/ABC123/stops"))));
  it("membro não altera o planejamento", () =>
    assertFails(setDoc(doc(db("carol"), "expeditions/ABC123"),
      { plan: { startTime: "05:00" } }, { merge: true })));
  it("SOS só em nome próprio", () =>
    assertFails(setDoc(doc(db("alice"), "expeditions/ABC123/alerts/a1"),
      { uid: "bob", name: "Bob", lat: 1, lng: 1, resolved: false })));
  it("membro aciona SOS", () =>
    assertSucceeds(setDoc(doc(db("alice"), "expeditions/ABC123/alerts/a2"),
      { uid: "alice", name: "Alice", lat: 1, lng: 1, resolved: false })));
});

describe("Perfil privado (users)", () => {
  it("dono lê o próprio perfil", () =>
    assertSucceeds(getDoc(doc(db("alice"), "users/alice"))));
  it("outro usuário não lê", () =>
    assertFails(getDoc(doc(db("bob"), "users/alice"))));
  it("outro usuário não escreve", () =>
    assertFails(setDoc(doc(db("bob"), "users/alice"), { consent: {} })));
});

describe("Motoclube", () => {
  it("quem não é membro não vê a lista", () =>
    assertFails(getDocs(collection(db("bob"), "clubs/CLUB01/members"))));
  it("membro vê a lista", () =>
    assertSucceeds(getDocs(collection(db("alice"), "clubs/CLUB01/members"))));
  it("coordenadas nunca vão para o clube", () =>
    assertFails(setDoc(doc(db("alice"), "clubs/CLUB01/members/alice"),
      { lat: -21, lng: -47 }, { merge: true })));
  it("app não acessa o registro de avisos", () =>
    assertFails(getDoc(doc(db("alice"), "clubs/CLUB01/rate/alice"))));
  it("membro pode sair do clube", () =>
    assertSucceeds(deleteDoc(doc(db("alice"), "clubs/CLUB01/members/alice"))));
});

describe("Alertas públicos", () => {
  const novo = (extra = {}) => ({
    type: "police", lat: -21, lng: -47, cell: "-210_-470", createdBy: "bob",
    confirmations: 1, dismissals: 0, expiresAt: inHours(1), ...extra,
  });
  it("cria alerta válido", () =>
    assertSucceeds(setDoc(doc(db("bob"), "hazards/h2"), novo())));
  it("recusa tipo inválido", () =>
    assertFails(setDoc(doc(db("bob"), "hazards/h3"), novo({ type: "ovni" }))));
  it("recusa prazo maior que 8 dias", () =>
    assertFails(setDoc(doc(db("bob"), "hazards/h4"), novo({ expiresAt: inHours(24 * 10) }))));
  it("recusa alerta em nome de outro", () =>
    assertFails(setDoc(doc(db("bob"), "hazards/h5"), novo({ createdBy: "alice" }))));
  it("voto altera os campos permitidos", () =>
    assertSucceeds(updateDoc(doc(db("bob"), "hazards/h1"),
      { confirmations: 2, expiresAt: inHours(3) })));
  it("voto não muda o tipo do alerta", () =>
    assertFails(updateDoc(doc(db("bob"), "hazards/h1"), { type: "police" })));
  it("ninguém apaga alertas pelo app", () =>
    assertFails(deleteDoc(doc(db("alice"), "hazards/h1"))));
});
