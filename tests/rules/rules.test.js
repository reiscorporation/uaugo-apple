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
  writeBatch, increment, serverTimestamp,
} = require("firebase/firestore");

let env;
const inHours = (h) => Timestamp.fromMillis(Date.now() + h * 3600e3);
// db("bob"): conta Google; anon("bob"): conta anônima do primeiro uso.
const db = (uid) =>
  (uid ? env.authenticatedContext(uid, { firebase: { sign_in_provider: "google.com" } })
    : env.unauthenticatedContext()).firestore();
const anon = (uid) =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: "anonymous" } }).firestore();
const PHOTO = "https://firebasestorage.googleapis.com/v0/b/helpaitechcomboio.firebasestorage.app/o/bikes%2F";

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
    await setDoc(doc(f, "expeditions/ABC123/alerts/sos1"),
      { uid: "carol", name: "Carol", lat: 1, lng: 1, resolved: false });
    await setDoc(doc(f, "clubs/CLUB01"), { name: "Clube", admins: ["alice"] });
    await setDoc(doc(f, "clubs/CLUB01/members/alice"), { name: "Alice", city: "", role: "admin" });
    await setDoc(doc(f, "clubs/CLUB01/members/carol"), { name: "Carol", city: "", role: "member" });
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
  it("SOS com posição inválida é recusado", () =>
    assertFails(setDoc(doc(db("alice"), "expeditions/ABC123/alerts/a3"),
      { uid: "alice", name: "Alice", lat: 500, lng: 1, resolved: false })));
  it("membro marca SOS como resolvido", () =>
    assertSucceeds(updateDoc(doc(db("alice"), "expeditions/ABC123/alerts/sos1"),
      { resolved: true, resolvedAt: serverTimestamp() })));
  it("ninguém muda a posição de um SOS", () =>
    assertFails(updateDoc(doc(db("alice"), "expeditions/ABC123/alerts/sos1"), { lat: 9 })));
  it("ninguém desfaz um SOS", () =>
    assertFails(updateDoc(doc(db("alice"), "expeditions/ABC123/alerts/sos1"), { resolved: false })));

  it("conta anônima não abre nem entra em expedição", async () => {
    await assertFails(getDoc(doc(anon("dave"), "expeditions/ABC123")));
    await assertFails(setDoc(doc(anon("dave"), "expeditions/ABC123/members/dave"), { name: "Dave" }));
  });
  it("conta anônima não cria expedição", () =>
    assertFails(setDoc(doc(anon("dave"), "expeditions/ABCD2345"), { name: "X", leaderId: "dave" })));
  it("com conta, cria expedição com código de 8", () =>
    assertSucceeds(setDoc(doc(db("bob"), "expeditions/ABCD2345"), { name: "Serra", leaderId: "bob" })));
  it("código novo curto é recusado", () =>
    assertFails(setDoc(doc(db("bob"), "expeditions/XYZ789"), { name: "Serra", leaderId: "bob" })));
  it("com conta e código, entra na expedição", () =>
    assertSucceeds(setDoc(doc(db("bob"), "expeditions/ABC123/members/bob"), { name: "Bob" })));
  it("não entra em expedição que não existe", () =>
    assertFails(setDoc(doc(db("bob"), "expeditions/NAOEXISTE/members/bob"), { name: "Bob" })));
  it("campo estranho no membro é recusado", () =>
    assertFails(setDoc(doc(db("alice"), "expeditions/ABC123/members/alice"),
      { admin: true }, { merge: true })));
  it("nome gigante é recusado", () =>
    assertFails(setDoc(doc(db("alice"), "expeditions/ABC123/members/alice"),
      { name: "x".repeat(500) }, { merge: true })));
  it("foto do próprio Storage é aceita", () =>
    assertSucceeds(setDoc(doc(db("alice"), "expeditions/ABC123/members/alice"),
      { bike: { brand: "Honda", photoUrl: `${PHOTO}alice%2F1.jpg?alt=media&token=t` } },
      { merge: true })));
  it("foto de site de terceiros é recusada", () =>
    assertFails(setDoc(doc(db("alice"), "expeditions/ABC123/members/alice"),
      { bike: { photoUrl: "https://exemplo.com/virus.jpg" } }, { merge: true })));
  it("foto da pasta de outro usuário é recusada", () =>
    assertFails(setDoc(doc(db("alice"), "expeditions/ABC123/members/alice"),
      { bike: { photoUrl: `${PHOTO}carol%2F1.jpg` } }, { merge: true })));
  it("caminhão com eixos (pedágio) é aceito", () =>
    assertSucceeds(setDoc(doc(db("alice"), "expeditions/ABC123/members/alice"),
      { bike: { style: "truck", axles: 6 } }, { merge: true })));
  it("carro com reboque é aceito; eixos inválidos são recusados", async () => {
    await assertSucceeds(setDoc(doc(db("alice"), "expeditions/ABC123/members/alice"),
      { bike: { style: "car", trailerAxles: 1 } }, { merge: true }));
    await assertFails(setDoc(doc(db("alice"), "expeditions/ABC123/members/alice"),
      { bike: { style: "truck", axles: 99 } }, { merge: true }));
  });
  it("app não lê o uso das funções", () =>
    assertFails(getDoc(doc(db("alice"), "usage/alice"))));
});

describe("Expedição: capitão e ferrolhos", () => {
  const exp = (u) => doc(db(u), "expeditions/ABC123");
  it("líder define capitão e até 3 ferrolhos", async () => {
    await assertSucceeds(updateDoc(exp("alice"), { captainId: "carol", sweepers: ["bob"] }));
    await assertFails(updateDoc(exp("alice"),
      { sweepers: ["a", "b", "c", "d"] }));
  });
  it("membro comum não define papéis nem a rota", async () => {
    await assertFails(updateDoc(exp("carol"), { captainId: "carol" }));
    await assertFails(updateDoc(exp("carol"), { plan: { polyline: "abc" } }));
  });
  it("capitão só altera a rota (e as manobras das paradas)", async () => {
    await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), "expeditions/ABC123"),
      { name: "Serra", leaderId: "alice", captainId: "carol", plan: { polyline: "" } }));
    await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), "expeditions/ABC123/stops/s1"),
      { name: "Posto", lat: 1, lng: 1, order: 1, steps: [] }));
    await assertSucceeds(updateDoc(exp("carol"), { plan: { polyline: "novo" } }));
    await assertFails(updateDoc(exp("carol"), { name: "Outro nome" }));
    await assertFails(updateDoc(exp("carol"), { captainId: "bob" }));
    await assertSucceeds(updateDoc(doc(db("carol"), "expeditions/ABC123/stops/s1"),
      { steps: [], legDistanceM: 100, legDurationS: 10 }));
    await assertFails(updateDoc(doc(db("carol"), "expeditions/ABC123/stops/s1"), { name: "X" }));
  });
});

describe("Perfil privado (users)", () => {
  it("dono lê o próprio perfil", () =>
    assertSucceeds(getDoc(doc(db("alice"), "users/alice"))));
  it("outro usuário não lê", () =>
    assertFails(getDoc(doc(db("bob"), "users/alice"))));
  it("outro usuário não escreve", () =>
    assertFails(setDoc(doc(db("bob"), "users/alice"), { consent: {} })));
  it("conta anônima grava o próprio aceite dos termos", () =>
    assertSucceeds(setDoc(doc(anon("dave"), "users/dave"), { terms: { version: "1.0" } })));
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
  it("ninguém entra no clube direto pelo banco (só com convite, pelo servidor)", () =>
    assertFails(setDoc(doc(db("bob"), "clubs/CLUB01/members/bob"),
      { name: "Bob", city: "Ribeirão Preto", bike: "Versys" })));
  it("ninguém cria clube direto pelo banco (só com código de ativação)", () =>
    assertFails(setDoc(doc(db("bob"), "clubs/CLUB2345"), { name: "C", createdBy: "bob" })));
  it("quem não é membro não abre o clube", () =>
    assertFails(getDoc(doc(db("bob"), "clubs/CLUB01"))));
  it("membro abre o clube", () =>
    assertSucceeds(getDoc(doc(db("alice"), "clubs/CLUB01"))));
  it("membro muda a própria cidade", () =>
    assertSucceeds(setDoc(doc(db("alice"), "clubs/CLUB01/members/alice"),
      { city: "Franca" }, { merge: true })));
  it("membro não se promove a administrador", () =>
    assertFails(setDoc(doc(db("carol"), "clubs/CLUB01/members/carol"),
      { role: "admin" }, { merge: true })));
  it("membro não remove outro membro", () =>
    assertFails(deleteDoc(doc(db("carol"), "clubs/CLUB01/members/alice"))));
  it("administrador remove um membro", () =>
    assertSucceeds(deleteDoc(doc(db("alice"), "clubs/CLUB01/members/carol"))));
  it("app não lê códigos de ativação nem convites", async () => {
    await assertFails(getDoc(doc(db("alice"), "clubActivations/ABCDEFGH2345")));
    await assertFails(getDoc(doc(db("alice"), "clubInvites/ABCD2345")));
    await assertFails(getDocs(collection(db("alice"), "clubInvites")));
  });
  it("membro pode sair do clube", () =>
    assertSucceeds(deleteDoc(doc(db("carol"), "clubs/CLUB01/members/carol"))));
  it("administrador só sai depois de deixar a função", () =>
    assertFails(deleteDoc(doc(db("alice"), "clubs/CLUB01/members/alice"))));
  it("clube antigo (presidentId): o presidente remove membro", async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      const f = c.firestore();
      await setDoc(doc(f, "clubs/OLD1"), { name: "Velho", presidentId: "bob" });
      await setDoc(doc(f, "clubs/OLD1/members/bob"), { name: "Bob", role: "president" });
      await setDoc(doc(f, "clubs/OLD1/members/dan"), { name: "Dan", role: "member" });
    });
    await assertSucceeds(deleteDoc(doc(db("bob"), "clubs/OLD1/members/dan")));
  });
});

describe("Alertas públicos", () => {
  const novo = (extra = {}) => ({
    type: "police", lat: -21, lng: -47, cell: "-210_-470", createdBy: "bob",
    confirmations: 1, dismissals: 0, expiresAt: inHours(1), ...extra,
  });
  it("cria alerta válido", () =>
    assertSucceeds(setDoc(doc(db("bob"), "hazards/h2"), novo())));
  it("aceita lombada", () =>
    assertSucceeds(setDoc(doc(db("bob"), "hazards/h8"), novo({ type: "bump" }))));
  it("recusa tipo inválido", () =>
    assertFails(setDoc(doc(db("bob"), "hazards/h3"), novo({ type: "ovni" }))));
  it("recusa prazo maior que 8 dias", () =>
    assertFails(setDoc(doc(db("bob"), "hazards/h4"), novo({ expiresAt: inHours(24 * 10) }))));
  it("recusa alerta em nome de outro", () =>
    assertFails(setDoc(doc(db("bob"), "hazards/h5"), novo({ createdBy: "alice" }))));
  it("recusa posição inválida", () =>
    assertFails(setDoc(doc(db("bob"), "hazards/h7"), novo({ lat: 200 }))));
  it("conta anônima não cria alerta, mas vê os alertas", async () => {
    await assertFails(setDoc(doc(anon("dave"), "hazards/h6"), novo({ createdBy: "dave" })));
    await assertSucceeds(getDoc(doc(anon("dave"), "hazards/h1")));
  });

  // Voto = registro votes/{uid} + contagem, no mesmo lote (como o app faz).
  const vote = (f, uid, up, changes) => {
    const b = writeBatch(f);
    b.set(doc(f, `hazards/h1/votes/${uid}`), { up, expiresAt: inHours(24) });
    b.update(doc(f, "hazards/h1"), changes);
    return b.commit();
  };
  const up = () => ({ confirmations: increment(1), expiresAt: inHours(3) });
  const removeVote = () => ({ dismissals: increment(1), expiresAt: serverTimestamp() });
  const setConfirmations = (n) => env.withSecurityRulesDisabled((c) =>
    updateDoc(doc(c.firestore(), "hazards/h1"), { confirmations: n }));

  it("confirma o alerta (1 voto)", () =>
    assertSucceeds(vote(db("bob"), "bob", true, up())));
  it("não vota duas vezes", async () => {
    await assertSucceeds(vote(db("bob"), "bob", true, up()));
    await assertFails(vote(db("bob"), "bob", true, up()));
  });
  it("não conta voto sem registrar o voto", () =>
    assertFails(updateDoc(doc(db("bob"), "hazards/h1"), { confirmations: 2, expiresAt: inHours(3) })));
  it("não soma mais de 1 por voto", () =>
    assertFails(vote(db("bob"), "bob", true, { confirmations: 50, expiresAt: inHours(3) })));
  it("autor não confirma o próprio alerta", () =>
    assertFails(vote(db("alice"), "alice", true, up())));
  it("um descarte sozinho não apaga alerta confirmado", async () => {
    await setConfirmations(3);
    await assertFails(vote(db("bob"), "bob", false, removeVote()));
    await assertSucceeds(vote(db("bob"), "bob", false, { dismissals: increment(1) }));
  });
  it("o 2º descarte remove o alerta", async () => {
    await assertSucceeds(vote(db("bob"), "bob", false, { dismissals: increment(1) }));
    await assertSucceeds(vote(db("carol"), "carol", false, removeVote()));
  });
  it("autor remove o próprio alerta", async () => {
    await setConfirmations(5);
    await assertSucceeds(vote(db("alice"), "alice", false, removeVote()));
  });
  it("voto não muda o tipo do alerta", () =>
    assertFails(vote(db("bob"), "bob", true, { ...up(), type: "police" })));
  it("conta anônima não vota", () =>
    assertFails(vote(anon("dave"), "dave", true, up())));
  it("ninguém apaga alertas pelo app", () =>
    assertFails(deleteDoc(doc(db("alice"), "hazards/h1"))));

  // ---- Alertas fixos (lombada, radar fixo, semáforo) e usuário Gold
  const far = () => Timestamp.fromDate(new Date(Date.UTC(2100, 0, 1)));
  const setDocAdmin = (p, data) => env.withSecurityRulesDisabled((c) =>
    setDoc(doc(c.firestore(), p), data));
  const fixedH1 = (extra = {}) => setDocAdmin("hazards/h1", {
    type: "bump", lat: -21, lng: -47, cell: "-210_-470", createdBy: "alice",
    confirmations: 3, dismissals: 0, expiresAt: far(), permanent: true, ...extra,
  });

  it("aceita veículo parado (alerta automático, 30 min)", () =>
    assertSucceeds(setDoc(doc(db("bob"), "hazards/sv1"),
      novo({ type: "stoppedVehicle", expiresAt: inHours(0.5) }))));
  it("aceita radar fixo e semáforo", async () => {
    await assertSucceeds(setDoc(doc(db("bob"), "hazards/h9"), novo({ type: "fixedRadar" })));
    await assertSucceeds(setDoc(doc(db("bob"), "hazards/h10"), novo({ type: "signal" })));
  });
  it("Gold cria lombada já fixa; comum não", async () => {
    await setDocAdmin("gold/bob", { since: inHours(0) });
    const fixed = { type: "bump", permanent: true, gold: true, expiresAt: far() };
    await assertSucceeds(setDoc(doc(db("bob"), "hazards/g1"), novo(fixed)));
    await assertFails(setDoc(doc(db("carol"), "hazards/g2"),
      novo({ ...fixed, createdBy: "carol" })));
  });
  it("Gold não deixa fixo o que muda (buraco)", async () => {
    await setDocAdmin("gold/bob", { since: inHours(0) });
    await assertFails(setDoc(doc(db("bob"), "hazards/g3"),
      novo({ type: "pothole", permanent: true, gold: true, expiresAt: far() })));
  });
  it("ninguém se declara Gold pelo app", async () => {
    await assertFails(setDoc(doc(db("bob"), "gold/bob"), { since: inHours(0) }));
    await assertFails(setDoc(doc(db("bob"), "hazards/g4"), novo({ gold: true })));
  });
  it("lombada fica fixa na 3ª confirmação, não antes", async () => {
    await setDocAdmin("hazards/h1", {
      type: "bump", lat: -21, lng: -47, cell: "-210_-470", createdBy: "alice",
      confirmations: 1, dismissals: 0, expiresAt: inHours(1),
    });
    const fix = { confirmations: increment(1), permanent: true, expiresAt: far() };
    await assertFails(vote(db("bob"), "bob", true, fix)); // seria a 2ª
    await assertSucceeds(vote(db("bob"), "bob", true, up())); // 2ª, normal
    await assertSucceeds(vote(db("carol"), "carol", true, fix)); // 3ª: fixa
  });
  it("confirmar alerta fixo não mexe no prazo", async () => {
    await fixedH1();
    await assertFails(vote(db("bob"), "bob", true, up()));
    await assertSucceeds(vote(db("bob"), "bob", true,
      { confirmations: increment(1), lastConfirmedAt: serverTimestamp() }));
  });
  it("alerta fixo comum sai com 3 'não está mais'", async () => {
    await fixedH1({ dismissals: 1 });
    await assertFails(vote(db("bob"), "bob", false, removeVote())); // seria o 2º
    await fixedH1({ dismissals: 2 });
    await assertSucceeds(vote(db("carol"), "carol", false, removeVote())); // 3º
  });
  it("alerta fixo Gold só sai com 5", async () => {
    await fixedH1({ dismissals: 3, gold: true });
    await assertFails(vote(db("bob"), "bob", false, removeVote())); // seria o 4º
    await fixedH1({ dismissals: 4, gold: true });
    await assertSucceeds(vote(db("carol"), "carol", false, removeVote())); // 5º
  });
});
