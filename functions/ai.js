/**
 * IA (Gemini, Vertex AI) para entender pedidos falados livres:
 * "o posto mais perto na minha rota", "restaurante bom e barato", "me leva
 * pra casa", "preciso calibrar o pneu" -> { action, category, query, cheap,
 * saved }. O app então faz a busca (maps.js "find") ou vai ao local salvo.
 *
 * Usa a conta de serviço da própria função (sem chave no app nem aqui).
 * Só o TEXTO do pedido vai para o Gemini (o áudio é reconhecido no celular
 * ou pelo Android). Teto por usuário: LIMITS.ai (maps.js).
 *
 * Função (chamada pelo app com httpsCallable):
 * - interpret: { text } -> { action, category, query, cheap, saved }
 */

const { HttpsError } = require("firebase-functions/v2/https");
const { FIND } = require("./maps");

const PROJECT = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "helpaitechcomboio";
const MODEL = "gemini-2.5-flash";
const URL = `https://aiplatform.googleapis.com/v1/projects/${PROJECT}/locations/global/publishers/google/models/${MODEL}:generateContent`;

const SYSTEM = "Você interpreta pedidos falados de um motorista ou motociclista num app de " +
  "navegação brasileiro. Responda só o JSON. action: \"find\" (achar um tipo de lugar perto " +
  "ou no caminho), \"goto\" (ir a um endereço, cidade ou lugar com nome) ou \"saved\" (ir para " +
  "casa ou para o trabalho). category: preencha só se o pedido for exatamente um destes tipos " +
  `(${Object.keys(FIND).join(", ")}); para pedidos mais específicos (ex.: loja de peças, ` +
  "pousada com garagem) deixe \"\" e ponha tudo em query. query: texto curto para buscar no " +
  "Google Maps (ex.: \"borracharia\", \"pousada com garagem Urubici\"; no goto, o destino). " +
  "cheap: pediu algo barato. saved: \"casa\", \"trabalho\" ou \"\".";

/** Token da conta de serviço (servidor de metadados do Google Cloud). */
async function accessToken() {
  const r = await fetch(
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
    { headers: { "Metadata-Flavor": "Google" }, signal: AbortSignal.timeout(5000) });
  return (await r.json()).access_token;
}

/** Confere e limpa a resposta da IA (nunca confia no formato). */
function clean(j) {
  const action = ["find", "goto", "saved"].includes(j?.action) ? j.action : "find";
  const category = typeof j?.category === "string" && FIND[j.category] ? j.category : "";
  const query = typeof j?.query === "string" ? j.query.trim().slice(0, 80) : "";
  const saved = ["casa", "trabalho"].includes(j?.saved) ? j.saved : "";
  return { action, category, query, cheap: j?.cheap === true, saved };
}

async function interpret(uid, data, countUse) {
  const text = typeof data?.text === "string" ? data.text.trim().slice(0, 200) : "";
  if (text.length < 2) throw new HttpsError("invalid-argument", "Pedido vazio.");
  await countUse(uid, "ai");
  const res = await fetch(URL, {
    method: "POST",
    headers: { Authorization: `Bearer ${await accessToken()}`, "content-type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: SYSTEM }] },
      contents: [{ role: "user", parts: [{ text }] }],
      generationConfig: {
        responseMimeType: "application/json",
        temperature: 0,
        responseSchema: {
          type: "OBJECT",
          properties: {
            action: { type: "STRING", enum: ["find", "goto", "saved"] },
            category: { type: "STRING" },
            query: { type: "STRING" },
            cheap: { type: "BOOLEAN" },
            saved: { type: "STRING" },
          },
          required: ["action", "category", "query", "cheap", "saved"],
        },
      },
    }),
    signal: AbortSignal.timeout(15000),
  });
  if (!res.ok) throw new HttpsError("unavailable", "IA indisponível agora.");
  const body = await res.json();
  const out = body?.candidates?.[0]?.content?.parts?.[0]?.text || "{}";
  try {
    return clean(JSON.parse(out));
  } catch (_) {
    return clean({});
  }
}

module.exports = { interpret, clean };
