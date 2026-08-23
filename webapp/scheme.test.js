const assert = require("node:assert/strict");
const test = require("node:test");
const {
  BOARD_SCHEME_INSTRUCTION,
  BOARD_SCHEME_SCHEMA,
  boardSchemePrompt,
  matchCatalogPart,
  modelKeys,
  normalizeReading,
} = require("./scheme");

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

test("the production instruction surveys title blocks and component schedules", () => {
  assert.match(BOARD_SCHEME_INSTRUCTION, /survey the complete document/i);
  assert.match(BOARD_SCHEME_INSTRUCTION, /title block/i);
  assert.match(BOARD_SCHEME_INSTRUCTION, /component schedule/i);
  assert.ok(BOARD_SCHEME_SCHEMA.required.includes("warnings"));
  assert.match(boardSchemePrompt("3918.24-12-1 MDB.pdf"), /select the matching board/i);
});

test("the generateContent response schema avoids unsupported JSON Schema fields", () => {
  const serialized = JSON.stringify(BOARD_SCHEME_SCHEMA);
  assert.doesNotMatch(serialized, /additionalProperties/);
  assert.match(serialized, /sourcePage/);
  assert.match(serialized, /warnings/);
});

test("printed ABB notation resolves conservatively to its catalog family", () => {
  const extendedCatalog = [
    ...CATALOG,
    { id: "abb-tmax-xt1", manufacturer: "ABB", model: "SACE Tmax XT1", type: "MCCB" },
    { id: "abb-f200", manufacturer: "ABB", model: "F200", type: "RCCB" },
  ];
  assert.ok(modelKeys("SACE Tmax XT1").includes("xt1"));
  assert.equal(matchCatalogPart(extendedCatalog, { manufacturer: "ABB", model: "XT1D" }).id, "abb-tmax-xt1");
  assert.equal(matchCatalogPart(extendedCatalog, { manufacturer: "ABB", model: "F204A" }).id, "abb-f200");
  assert.equal(matchCatalogPart(CATALOG, { manufacturer: "ABB", model: "S201M" }).id, "abb-s201-1p");
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
    board: {
      number: "3918.24-1",
      name: "Main Distribution Board",
      cabinetCount: 3,
      supplyVoltage: "400/230V AC",
      standards: ["IEC 61439-2"],
    },
    components: [
      { manufacturer: "ABB", model: "S201", type: "MCB", quantity: 12, reference: "Q1", rawText: "ABB S201 C16 x12", sourcePage: 42 },
      { manufacturer: "Nobody", model: "ZX9000", type: "Relay", quantity: 2, rawText: "Nobody ZX9000 24VDC" },
    ],
    warnings: ["Page 7 is rotated and partly unreadable."],
  }, CATALOG);

  assert.equal(result.board.number, "3918.24-1");
  assert.equal(result.board.cabinetCount, 3);
  assert.equal(result.board.supplyVoltage, "400/230V AC");
  assert.deepEqual(result.board.standards, ["IEC 61439-2"]);
  assert.equal(result.components.length, 1);
  assert.deepEqual(
    { partID: result.components[0].partID, quantity: result.components[0].quantity },
    { partID: "abb-s201-1p", quantity: 12 },
  );
  assert.equal(result.components[0].rawText, "ABB S201 C16 x12");
  assert.equal(result.components[0].sourcePage, 42);
  assert.equal(result.unmatched.length, 1);
  assert.equal(result.unmatched[0].description, "Nobody ZX9000 24VDC");
  assert.deepEqual(result.warnings, ["Page 7 is rotated and partly unreadable."]);
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
