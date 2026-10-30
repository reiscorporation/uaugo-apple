/**
 * gold.js — Usuário Ouro (Gold) automático
 *
 * O que faz: regras do programa Ouro, sem acesso ao banco (testáveis):
 *  - statsDelta: o que uma mudança num alerta soma nas estatísticas de
 *    contribuição de quem o criou (userStats/{uid}: created, confirmed,
 *    removed). Os alertas se apagam sozinhos (TTL); as estatísticas ficam.
 *  - isEligible: a pessoa cumpre os critérios (Termos de Uso, item 7)?
 * Quem usa: functions/index.js (onHazardStats e updateGold).
 * Onde mexer: os números do programa estão em GOLD (e nos Termos de Uso).
 */

/** Critérios do Ouro (iguais aos dos Termos de Uso). */
const GOLD = {
  minAccountDays: 30,      // conta com pelo menos 30 dias
  minConfirmed: 15,        // pelo menos 15 alertas confirmados por outros
  maxRemovedRatio: 0.1,    // no máximo 1 em cada 10 removidos como inexistentes
};

/** Alertas automáticos (veículo parado) não contam: não foram reportados. */
const IGNORED_TYPES = new Set(["stoppedVehicle"]);

function ms(t) {
  if (!t) return 0;
  if (typeof t.toMillis === "function") return t.toMillis();
  if (t instanceof Date) return t.getTime();
  return Number(t) || 0;
}

/**
 * Quanto somar em userStats/{createdBy} quando o alerta muda de [before]
 * para [after] (before null = criado agora). [now] em ms.
 * - created: alerta novo;
 * - confirmed: primeira confirmação de outra pessoa (1 -> 2);
 * - removed: a comunidade tirou do mapa como "não está mais" (prazo virou
 *   "agora" com 2 votos contra ou mais votos contra que a favor). O autor
 *   tirando o próprio alerta (1 voto, sem confirmação de outros) não conta.
 */
function statsDelta(before, after, now = Date.now()) {
  const d = { created: 0, confirmed: 0, removed: 0 };
  const a = after || {};
  const uid = a.createdBy || (before && before.createdBy);
  if (!uid || uid === "removido" || IGNORED_TYPES.has(a.type || (before && before.type))) {
    return { uid: null, ...d };
  }
  if (!before) {
    d.created = 1;
    return { uid, ...d };
  }
  if ((before.confirmations || 1) < 2 && (a.confirmations || 1) >= 2) d.confirmed = 1;
  const wasActive = ms(before.expiresAt) > now;
  const endedNow = ms(a.expiresAt) <= now + 60 * 1000;
  const dis = a.dismissals || 0;
  if (wasActive && endedNow && dis > (before.dismissals || 0) &&
      (dis >= 2 || dis > (a.confirmations || 1))) {
    d.removed = 1;
  }
  return { uid, ...d };
}

/**
 * Cumpre os critérios do Ouro? [stats] = {created, confirmed, removed};
 * [accountCreatedMs] = criação da conta (Firebase Auth); [now] em ms.
 */
function isEligible(stats, accountCreatedMs, now = Date.now()) {
  const s = stats || {};
  const days = (now - (accountCreatedMs || now)) / 86400000;
  if (days < GOLD.minAccountDays) return false;
  if ((s.confirmed || 0) < GOLD.minConfirmed) return false;
  const created = Math.max(s.created || 0, s.confirmed || 0);
  return (s.removed || 0) <= created * GOLD.maxRemovedRatio;
}

module.exports = { GOLD, statsDelta, isEligible };
