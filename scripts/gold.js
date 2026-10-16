// Usuários GOLD (só a HelpAITech concede).
//
// Gold = o responsável e quem ele convidar (ex.: muitas horas de uso). Alerta
// de lombada, radar fixo ou semáforo marcado por um Gold já nasce FIXO no mapa
// (não expira) e só sai com 5 "não está mais" (firestore.rules, hazards).
// A lista fica em Firestore → gold/{uid}; o app só confere o próprio.
//
// Uso (na raiz do projeto, com o gcloud logado na conta da HelpAITech):
//   node scripts/gold.js --dar pessoa@gmail.com "motivo"   # concede
//   node scripts/gold.js --tirar pessoa@gmail.com          # retira
//   node scripts/gold.js --listar
// A pessoa precisa ter entrado no app com esse e-mail (conta criada).

const { execSync } = require("child_process");

const PROJECT = "helpaitechcomboio";
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const token = execSync("gcloud auth print-access-token", { encoding: "utf8", shell: true }).trim();
const headers = {
  Authorization: `Bearer ${token}`,
  "Content-Type": "application/json",
  "x-goog-user-project": PROJECT,
};

/** uid da conta com este e-mail (Firebase Auth), ou null. */
async function uidOf(email) {
  const r = await fetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:lookup`,
    { method: "POST", headers, body: JSON.stringify({ email: [email] }) });
  const j = await r.json();
  return j.users?.[0]?.localId || null;
}

async function give(email, note) {
  const uid = await uidOf(email);
  if (!uid) return console.log(`Nenhuma conta com o e-mail ${email} (a pessoa já entrou no app?)`);
  const fields = {
    email: { stringValue: email },
    note: { stringValue: note || "" },
    since: { timestampValue: new Date().toISOString() },
  };
  const r = await fetch(`${BASE}/gold/${uid}`, { method: "PATCH", headers, body: JSON.stringify({ fields }) });
  console.log(r.ok ? `GOLD concedido a ${email}` : `Falhou (${r.status})`);
}

async function take(email) {
  const uid = await uidOf(email);
  if (!uid) return console.log(`Nenhuma conta com o e-mail ${email}`);
  const r = await fetch(`${BASE}/gold/${uid}`, { method: "DELETE", headers });
  console.log(r.ok ? `GOLD retirado de ${email}` : `Falhou (${r.status})`);
}

async function list() {
  const r = await (await fetch(`${BASE}/gold?pageSize=300`, { headers })).json();
  console.table((r.documents || []).map((d) => ({
    email: d.fields?.email?.stringValue || "",
    desde: (d.fields?.since?.timestampValue || "").slice(0, 10),
    motivo: d.fields?.note?.stringValue || "",
  })));
}

(async () => {
  const [cmd, email, note] = process.argv.slice(2);
  if (cmd === "--listar") return list();
  if (cmd === "--dar" && email) return give(email.trim().toLowerCase(), note);
  if (cmd === "--tirar" && email) return take(email.trim().toLowerCase());
  console.log('Uso: node scripts/gold.js --dar email "motivo" | --tirar email | --listar');
})();
