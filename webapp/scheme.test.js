const assert = require("node:assert/strict");
const test = require("node:test");
const { matchCatalogPart, normalizeReading } = require("./scheme");

const CATALOG = [
  { id: "abb-s201-1p", manufacturer: "ABB", model: "S201", type: "MCB" },
  { id: "abb-s202-2p", manufacturer: "ABB", model: "S202", type: "MCB" },
  { id: "schneider-ic60n", manufacturer: "Schneider", model: "Acti9 iC60N", type: "MCB" },
  { id: "siemens-5sy", manufacturer: "Siemens", model: "SENTRON 5SY", type: "MCB" },
  { id: "eaton-faz", manufacturer: "Eaton", model: "FAZ", type: "MCB" },
];

test("a part named exactly as the catalog spells it matches", () => {
  const hit = matchCatalogPart(CATALOG, { manufacturer: "ABB", model: "S201", type: "MCB" });
  assert.equal(hit.id, "abb-s201-1p");
});

test("spelling and spacing differences on the drawing still match", () => {
  // Drawings write the same breaker a dozen ways.
  for (const model of ["iC60N", "Acti9 IC60N", "acti 9 ic60n"]) {
    const hit = matchCatalogPart(CATALOG, { manufacturer: "Schneider", model, type: "MCB" });
    assert.equal(hit && hit.id, "schneider-ic60n", `failed for ${model}`);
  }
});

test("a model belonging to another brand is refused, not coerced", () => {
  // The drawing says Siemens; the only S201 in the catalog is ABB. Putting an
  // ABB breaker on a Siemens line would be built as-is.
  assert.equal(matchCatalogPart(CATALOG, { manufacturer: "Siemens", model: "S201" }), null);
});

test("a bare model number is still matched when it is unambiguous", () => {
  const hit = matchCatalogPart(CATALOG, { model: "FAZ" });
  assert.equal(hit.id, "eaton-faz");
});

test("an ambiguous read is handed back rather than guessed", () => {
  const ambiguous = [
    { id: "a-x100", manufacturer: "ABB", model: "X100", type: "MCB" },
    { id: "b-x100", manufacturer: "ABB", model: "X100", type: "MCB" },
  ];
  assert.equal(matchCatalogPart(ambiguous, { manufacturer: "ABB", model: "X100", type: "MCB" }), null);
});

test("noise too short to identify a part never matches", () => {
  assert.equal(matchCatalogPart(CATALOG, { model: "S" }), null);
  assert.equal(matchCatalogPart(CATALOG, { model: "" }), null);
  assert.equal(matchCatalogPart(CATALOG, {}), null);
});

test("a reading is split into catalog parts and lines needing a person", () => {
  const result = normalizeReading({
    board: { number: "3918.24-1", name: "Main Distribution Board", cabinetCount: 3 },
    components: [
      { manufacturer: "ABB", model: "S201", type: "MCB", quantity: 12, reference: "Q1" },
      { manufacturer: "Nobody", model: "ZX9000", type: "Relay", quantity: 2 },
    ],
  }, CATALOG);

  assert.equal(result.board.number, "3918.24-1");
  assert.equal(result.board.cabinetCount, 3);
  assert.equal(result.components.length, 1);
  assert.deepEqual(
    { partID: result.components[0].partID, quantity: result.components[0].quantity },
    { partID: "abb-s201-1p", quantity: 12 },
  );
  assert.equal(result.unmatched.length, 1);
  assert.match(result.unmatched[0].description, /ZX9000/);
});

test("model output is clamped before it can reach a board draft", () => {
  const result = normalizeReading({
    board: {
      number: "N".repeat(500),
      cabinetCount: 9999,
      notes: "x".repeat(5000),
    },
    components: [
      { manufacturer: "ABB", model: "S201", quantity: -4 },
      { manufacturer: "ABB", model: "S202", quantity: 1e9 },
    ],
  }, CATALOG);

  assert.equal(result.board.number.length, 60);
  assert.equal(result.board.cabinetCount, 40);
  assert.equal(result.board.notes.length, 600);
  assert.equal(result.components[0].quantity, 1);
  assert.equal(result.components[1].quantity, 999);
});

test("a reading with nothing usable produces empty lists, not throws", () => {
  const empty = normalizeReading({}, CATALOG);
  assert.deepEqual(empty.components, []);
  assert.deepEqual(empty.unmatched, []);
  assert.equal(empty.board.number, "");
  assert.equal(empty.board.cabinetCount, 1);

  assert.doesNotThrow(() => normalizeReading(null, CATALOG));
  assert.doesNotThrow(() => normalizeReading({ components: "not an array" }, CATALOG));
});
