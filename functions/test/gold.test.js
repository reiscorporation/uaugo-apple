// Testes do programa Ouro (functions/gold.js). Sem emulador:
//   node --test functions/test/gold.test.js
const { describe, it } = require("node:test");
const assert = require("assert");
const { statsDelta, isEligible } = require("../gold");

const NOW = Date.UTC(2026, 9, 30, 12);
const later = (h) => NOW + h * 3600000;

describe("Ouro: estatísticas dos alertas", () => {
  it("alerta novo conta como criado", () => {
    const d = statsDelta(null, { createdBy: "u1", type: "radar" }, NOW);
    assert.deepStrictEqual(d, { uid: "u1", created: 1, confirmed: 0, removed: 0 });
  });
  it("primeira confirmação de outra pessoa conta uma vez", () => {
    const b = { createdBy: "u1", type: "radar", confirmations: 1, dismissals: 0, expiresAt: later(4) };
    assert.strictEqual(statsDelta(b, { ...b, confirmations: 2 }, NOW).confirmed, 1);
    assert.strictEqual(statsDelta({ ...b, confirmations: 2 }, { ...b, confirmations: 3 }, NOW).confirmed, 0);
  });
  it("removido pela comunidade (2 votos) conta; o autor tirando o próprio não", () => {
    const b = { createdBy: "u1", type: "radar", confirmations: 1, dismissals: 1, expiresAt: later(4) };
    assert.strictEqual(statsDelta(b, { ...b, dismissals: 2, expiresAt: NOW }, NOW).removed, 1);
    const own = { ...b, dismissals: 0 };
    assert.strictEqual(statsDelta(own, { ...own, dismissals: 1, expiresAt: NOW }, NOW).removed, 0);
  });
  it("veículo parado (automático) não conta", () => {
    assert.strictEqual(statsDelta(null, { createdBy: "u1", type: "stoppedVehicle" }, NOW).uid, null);
  });
});

describe("Ouro: critérios", () => {
  const old = NOW - 40 * 86400000;
  it("30 dias, 15 confirmados e até 1 em 10 removidos: é Ouro", () => {
    assert.ok(isEligible({ created: 20, confirmed: 15, removed: 2 }, old, NOW));
  });
  it("conta nova, poucos confirmados ou muitos removidos: não é", () => {
    assert.ok(!isEligible({ created: 20, confirmed: 15, removed: 0 }, NOW - 10 * 86400000, NOW));
    assert.ok(!isEligible({ created: 20, confirmed: 14, removed: 0 }, old, NOW));
    assert.ok(!isEligible({ created: 20, confirmed: 15, removed: 3 }, old, NOW));
  });
});
