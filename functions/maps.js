/**
 * Rotas (Directions API) e busca de lugares (Places API) pelo SERVIDOR.
 *
 * Por que pelo servidor: a chave do Google fica aqui (functions/.env,
 * MAPS_SERVER_KEY), e não dentro do app, de onde qualquer um poderia
 * extraí-la e gerar cobranças na conta. Só atende usuários logados (e, com o
 * App Check ligado, só o app verdadeiro), com limite diário por usuário.
 *
 * Funções (chamadas pelo app com httpsCallable):
 * - directions: { origin, destination, waypoints?, avoid?, alternatives?,
 *                 traffic? }  ->  a resposta da Directions API
 * - places:     { action: "autocomplete", input, sessionToken, lat?, lng? }
 *               { action: "details", placeId, sessionToken }
 *               { action: "find", category, cheap?, openNow?, lat, lng,
 *                 polyline?, text? }  ->  lugares de um tipo perto ou NO
 *                 CAMINHO; category "text" = o que o piloto falou ("pizzaria")
 *                 ("UauGo, procurar posto"); limite próprio (LIMITS.find).
 */

const { HttpsError } = require("firebase-functions/v2/https");
const { getFirestore } = require("firebase-admin/firestore");

/**
 * Tetos por usuário por dia. Não são limite de uso (decisão de 2026-10-15:
 * sem limite para quem usa de verdade); só protegem a conta do Google de
 * robô ou de um defeito que consulte sem parar.
 */
const LIMITS = { directions: 1000, places: 3000, find: 200, ai: 200 };

/**
 * Categorias de "procurar" (a mesma lista do app, lib/logic/find_places.dart):
 * texto da busca e tipo do Google (filtra só esse tipo, se houver).
 */
const FIND = {
  fuel: { q: "posto de combustível", type: "gas_station" },
  food: { q: "restaurante", type: "restaurant" },
  snack: { q: "lanchonete", type: null },
  cafe: { q: "café", type: "cafe" },
  bakery: { q: "padaria", type: "bakery" },
  lodging: { q: "hotel pousada", type: "lodging" },
  mechanic: { q: "oficina mecânica", type: "car_repair" },
  tire: { q: "borracharia", type: null },
  pharmacy: { q: "farmácia", type: "pharmacy" },
  hospital: { q: "hospital", type: "hospital" },
  atm: { q: "caixa eletrônico", type: "atm" },
  market: { q: "supermercado", type: "supermarket" },
  pizza: { q: "pizzaria", type: "pizza_restaurant" },
  bbq: { q: "churrascaria", type: null },
  burger: { q: "hamburgueria", type: "hamburger_restaurant" },
  icecream: { q: "sorveteria", type: "ice_cream_shop" },
  acai: { q: "açaí", type: null },
  bar: { q: "bar", type: "bar" },
  parking: { q: "estacionamento", type: "parking" },
  carwash: { q: "lava-rápido", type: "car_wash" },
};
const POLYLINE = /^[\x3f-\x7e]{2,100000}$/; // caracteres de polilinha codificada

/** Idioma pedido pelo app ("en" ou português, o padrão). */
const langOf = (data) => (data && data.lang === "en" ? "en" : "pt-BR");

const COORD = /^-?\d{1,2}(\.\d+)?,-?\d{1,3}(\.\d+)?$/;
const key = () => process.env.MAPS_SERVER_KEY || "";

/** Conta o uso do dia (users/{uid} não é usado: coleção só do servidor). */
async function countUse(uid, kind) {
  const db = getFirestore();
  const day = new Date().toISOString().slice(0, 10);
  const ref = db.doc(`usage/${uid}`);
  await db.runTransaction(async (tx) => {
    const d = (await tx.get(ref)).data() || {};
    const n = d.day === day ? d[kind] || 0 : 0;
    if (n >= LIMITS[kind]) {
      throw new HttpsError("resource-exhausted",
        "Limite diário de consultas atingido. Tente amanhã.");
    }
    tx.set(ref, d.day === day ? { ...d, [kind]: n + 1 } : { day, [kind]: 1 });
  });
}

function requireUser(req) {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Faça login.");
  if (!key()) throw new HttpsError("failed-precondition", "Rotas indisponíveis.");
  return uid;
}

async function directions(req) {
  const uid = requireUser(req);
  const { origin, destination, waypoints, avoid, alternatives, traffic } = req.data || {};
  if (!COORD.test(origin || "") || !COORD.test(destination || "")) {
    throw new HttpsError("invalid-argument", "Origem ou destino inválido.");
  }
  const wps = typeof waypoints === "string" && waypoints ? waypoints.split("|") : [];
  if (wps.length > 23 || !wps.every((w) => COORD.test(w))) {
    throw new HttpsError("invalid-argument", "Paradas inválidas.");
  }
  const av = (Array.isArray(avoid) ? avoid : [])
    .filter((a) => ["tolls", "highways", "ferries"].includes(a));
  await countUse(uid, "directions");

  const p = new URLSearchParams({
    origin, destination, mode: "driving", language: langOf(req.data), key: key(),
  });
  if (wps.length) p.set("waypoints", wps.join("|"));
  if (av.length) p.set("avoid", av.join("|"));
  if (alternatives === true && !wps.length) p.set("alternatives", "true");
  if (traffic === true) p.set("departure_time", "now");
  let body = await askDirections(p);
  // Sem rota (ex.: ponto no meio do deserto, longe de estrada): troca cada
  // ponto que não é a saída pelo lugar com estrada mais próximo (cidade ou
  // posto, até 50 km) e tenta de novo. Só nesse caso (custa uma busca).
  if (body.status === "ZERO_RESULTS" || body.status === "NOT_FOUND") {
    const pts = [...wps, destination];
    const near = await Promise.all(pts.map(nearestRoadPlace));
    if (near.some((x) => x)) {
      const fixed = pts.map((pt, i) => near[i] ? `${near[i].lat},${near[i].lng}` : pt);
      p.set("destination", fixed[fixed.length - 1]);
      if (wps.length) p.set("waypoints", fixed.slice(0, -1).join("|"));
      const again = await askDirections(p);
      if (again.status === "OK") {
        again.snapped = near.map((x, i) => x ? { index: i + 1, ...x } : null).filter(Boolean);
        body = again;
      }
    }
  }
  // Nunca devolve mensagens internas do Google (podem citar a chave).
  delete body.error_message;
  return body;
}

/** Uma chamada à Directions API. */
async function askDirections(p) {
  const res = await fetch(`https://maps.googleapis.com/maps/api/directions/json?${p}`,
    { signal: AbortSignal.timeout(15000) });
  return res.json();
}

/**
 * Lugar com estrada mais próximo de "lat,lng" (cidade, vila ou posto, até
 * 50 km), pela busca de lugares. Null se não achar.
 */
async function nearestRoadPlace(coord) {
  const [lat, lng] = coord.split(",").map(Number);
  try {
    const res = await fetch("https://places.googleapis.com/v1/places:searchNearby", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "X-Goog-Api-Key": key(),
        "X-Goog-FieldMask": "places.displayName,places.location",
      },
      body: JSON.stringify({
        includedTypes: ["locality", "gas_station", "lodging", "tourist_attraction"],
        maxResultCount: 1,
        rankPreference: "DISTANCE",
        locationRestriction: { circle: { center: { latitude: lat, longitude: lng }, radius: 50000 } },
        languageCode: "pt-BR",
      }),
      signal: AbortSignal.timeout(8000),
    });
    const j = await res.json();
    const pl = (j.places || [])[0];
    if (!pl?.location) return null;
    return { lat: pl.location.latitude, lng: pl.location.longitude, name: pl.displayName?.text || "" };
  } catch (_) {
    return null;
  }
}

async function places(req) {
  const uid = requireUser(req);
  const { action, input, sessionToken, lat, lng, placeId } = req.data || {};
  const session = typeof sessionToken === "string" ? sessionToken.slice(0, 64) : undefined;
  if (action === "find") return find(uid, req.data || {});
  await countUse(uid, "places");

  if (action === "autocomplete") {
    if (typeof input !== "string" || input.trim().length < 2 || input.length > 120) {
      throw new HttpsError("invalid-argument", "Busca inválida.");
    }
    const body = { input: input.trim(), languageCode: langOf(req.data), sessionToken: session };
    if (typeof lat === "number" && typeof lng === "number" &&
        Math.abs(lat) <= 90 && Math.abs(lng) <= 180) {
      body.locationBias = {
        circle: { center: { latitude: lat, longitude: lng }, radius: 50000.0 },
      };
      // Devolve a distância de cada sugestão: o app ordena da mais perto.
      body.origin = { latitude: lat, longitude: lng };
    }
    const res = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
      method: "POST",
      headers: { "content-type": "application/json", "X-Goog-Api-Key": key() },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(10000),
    });
    const j = await res.json();
    return { suggestions: j.suggestions || [] };
  }

  if (action === "details") {
    if (typeof placeId !== "string" || !/^[\w-]{10,300}$/.test(placeId)) {
      throw new HttpsError("invalid-argument", "Lugar inválido.");
    }
    const q = new URLSearchParams({ languageCode: langOf(req.data) });
    if (session) q.set("sessionToken", session);
    const res = await fetch(`https://places.googleapis.com/v1/places/${placeId}?${q}`, {
      headers: {
        "X-Goog-Api-Key": key(),
        // Só endereço e posição: faixa "Essentials" (mais barata). O nome
        // do lugar o app já tem (é o texto da sugestão escolhida).
        "X-Goog-FieldMask": "formattedAddress,location",
      },
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) return {};
    const j = await res.json();
    return { formattedAddress: j.formattedAddress, location: j.location };
  }

  throw new HttpsError("invalid-argument", "Ação inválida.");
}

/**
 * "Procurar posto/restaurante...": Text Search do Google. Com a rota
 * ([polyline]), busca AO LONGO dela (o Google prioriza o menor desvio);
 * sem rota, perto do piloto, do mais próximo ao mais longe.
 */
async function find(uid, d) {
  // "text": pedido livre falado ("loja de moto"); só o texto, sem tipo.
  const free = d.category === "text" && typeof d.text === "string" &&
    d.text.trim().length >= 2 && d.text.length <= 80;
  const cat = free ? { q: d.text.trim(), type: null } : FIND[d.category];
  const { lat, lng, polyline } = d;
  if (!cat || typeof lat !== "number" || typeof lng !== "number" ||
      Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    throw new HttpsError("invalid-argument", "Busca inválida.");
  }
  const along = typeof polyline === "string" && POLYLINE.test(polyline);
  await countUse(uid, "find");

  const search = async (priceLevels) => {
    const body = {
      textQuery: cat.q, languageCode: "pt-BR", regionCode: "BR", maxResultCount: 8,
    };
    if (cat.type) {
      body.includedType = cat.type;
      body.strictTypeFiltering = true;
    }
    if (d.openNow === true) body.openNow = true;
    if (priceLevels) body.priceLevels = priceLevels;
    if (along) {
      body.searchAlongRouteParameters = { polyline: { encodedPolyline: polyline } };
    } else {
      body.locationBias = {
        circle: { center: { latitude: lat, longitude: lng }, radius: 15000.0 },
      };
      body.rankPreference = "DISTANCE";
    }
    const res = await fetch("https://places.googleapis.com/v1/places:searchText", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "X-Goog-Api-Key": key(),
        "X-Goog-FieldMask": "places.id,places.displayName,places.formattedAddress," +
          "places.location,places.priceLevel,places.rating," +
          "places.currentOpeningHours.openNow",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) return [];
    return (await res.json()).places || [];
  };

  // "Barato": primeiro só os baratos; se não houver, os de preço moderado.
  let list = await search(d.cheap === true ? ["PRICE_LEVEL_INEXPENSIVE"] : null);
  if (!list.length && d.cheap === true) {
    list = await search(["PRICE_LEVEL_INEXPENSIVE", "PRICE_LEVEL_MODERATE"]);
  }
  return {
    places: list.filter((p) => p.location).map((p) => ({
      id: p.id,
      name: p.displayName?.text || cat.q,
      address: p.formattedAddress || "",
      lat: p.location.latitude,
      lng: p.location.longitude,
      price: p.priceLevel || null,
      rating: p.rating || null,
      open: p.currentOpeningHours?.openNow ?? null,
    })),
    along,
  };
}

module.exports = { directions, places, FIND, countUse, requireUser };
