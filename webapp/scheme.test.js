const assert = require("node:assert/strict");
const test = require("node:test");
const {
  BOARD_SCHEME_INSTRUCTION,
  BOARD_SCHEME_SCHEMA,
  ampereRating,
  boardSchemePrompt,
  breakerCurve,
  matchCatalogPart,
  modelKeys,
  normalizeReading,
  poleKey,
  resolveBoardManufacturer,
  targetBoardNumberFromFileName,
} = require("./scheme");

const CATALOG = [
  { id: "abb-s201-1p", manufacturer: "ABB", model: "S201", type: "MCB", rating: "Set A", poles: "1P", curve: "B/C/D Curve" },
  { id: "abb-s202-2p", manufacturer: "ABB", model: "S202", type: "MCB", rating: "Set A", poles: "2P", curve: "B/C/D Curve" },
  { id: "abb-s203-3p", manufacturer: "ABB", model: "S203", type: "MCB", rating: "0.5-63A", poles: "3P", curve: "B/C/D Curve" },
  { id: "abb-sn201-1pn", manufacturer: "ABB", model: "SN201", type: "MCB", rating: "Set A", poles: "1P+N", curve: "B/C Curve" },
  { id: "schneider-ic60n", manufacturer: "Schneider", model: "Acti9 iC60N", type: "MCB" },
  { id: "siemens-5sy", manufacturer: "Siemens", model: "SENTRON 5SY", type: "MCB" },
  { id: "eaton-faz", manufacturer: "Eaton", model: "FAZ", type: "MCB" },
  { id: "allen-bradley-800f-push-button", manufacturer: "Allen-Bradley", model: "800F push button", type: "Push Button", rating: "22.5mm" },
  { id: "allen-bradley-800f-selector", manufacturer: "Allen-Bradley", model: "800F selector switch", type: "Selector Switch", rating: "22.5mm" },
  { id: "allen-bradley-800f-pilot-light", manufacturer: "Allen-Bradley", model: "800F pilot light", type: "Pilot Light", rating: "22.5mm" },
  { id: "allen-bradley-802t-door-switch", manufacturer: "Allen-Bradley", model: "802T standard limit switch", type: "Door Switch", rating: "NEMA 4/13" },
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

test("the production instruction counts unique devices from schematic pages", () => {
  assert.match(BOARD_SCHEME_INSTRUCTION, /survey the complete document/i);
  assert.match(BOARD_SCHEME_INSTRUCTION, /title block/i);
  assert.match(BOARD_SCHEME_INSTRUCTION, /unique physical device tags\/references/i);
  assert.match(BOARD_SCHEME_INSTRUCTION, /never use its summarized quantity\s+as the count/i);
  assert.match(BOARD_SCHEME_INSTRUCTION, /count its device tag once across the entire\s+PDF/i);
  assert.match(BOARD_SCHEME_INSTRUCTION, /FIRL 6A \+ N/i);
  assert.match(BOARD_SCHEME_INSTRUCTION, /main incomer once in components/i);
  assert.match(BOARD_SCHEME_INSTRUCTION, /door elevations, control\s+station layouts and operator-device schedules/i);
  assert.match(BOARD_SCHEME_INSTRUCTION, /Allen-Bradley may be printed as AB, A-B/i);
  assert.match(BOARD_SCHEME_INSTRUCTION, /כיתאו אליקטריק/);
  assert.ok(BOARD_SCHEME_SCHEMA.required.includes("warnings"));
  assert.ok(BOARD_SCHEME_SCHEMA.required.includes("pageBoards"));
  assert.ok(BOARD_SCHEME_SCHEMA.required.includes("doorDevices"));
  assert.match(boardSchemePrompt("3918.24-12-1 MDB.pdf"), /extract only pages mapped to this exact board number/i);
  assert.match(boardSchemePrompt("3918.24-12-1 MDB.pdf"), /MANDATORY TARGET BOARD: "3918.24-12-1"/i);
  assert.match(boardSchemePrompt("3918.24-12-1 MDB.pdf"), /not from the final-page parts list/i);
  assert.match(boardSchemePrompt("3918.24-12-1 MDB.pdf"), /dedicated exhaustive door-layout pass/i);
  assert.match(boardSchemePrompt("3918.24-12-1 MDB.pdf"), /never stop after the first recognized operator/i);
  assert.match(boardSchemePrompt("3918.24-12-1 MDB.pdf"), /closest supported PanelVault type/i);
  assert.match(boardSchemePrompt("3918.24-12-1 MDB.pdf"), /"components":\[\{/);
  assert.match(boardSchemePrompt("3918.24-12-1 MDB.pdf"), /"mainBreakerModel":""/);
});

test("the exhaustive door inventory keeps every switch and lamp without double-counting schematic tags", () => {
  const result = normalizeReading({
    board: { number: "3918.24-12-1" },
    pageBoards: [{ page: 4, boardNumber: "3918.24-12-1" }],
    components: [{
      manufacturer: "A-B", model: "800F", type: "selector", quantity: 1,
      reference: "SS1", rawText: "SS1 HAND-OFF-AUTO", sourcePage: 2,
      boardNumber: "3918.24-12-1",
    }],
    doorDevices: [
      {
        manufacturer: "Allen Bradley", model: "800F-X", type: "Selector Switch", quantity: 1,
        reference: "SS1", rawText: "SS1 HAND-OFF-AUTO", sourcePage: 4,
        boardNumber: "3918.24-12-1",
      },
      {
        manufacturer: "Allen Bradley", model: "800F-X", type: "Selector Switch", quantity: 1,
        reference: "SS2", rawText: "SS2 LOCAL-REMOTE", sourcePage: 4,
        boardNumber: "3918.24-12-1",
      },
      {
        manufacturer: "Rockwell", model: "800F-P", type: "Indicator Lamp", quantity: 3,
        reference: "PL1-PL3", rawText: "green RUN, red TRIP, amber HEALTHY", sourcePage: 4,
        boardNumber: "3918.24-12-1",
      },
      {
        manufacturer: "", model: "", type: "Pilot Light", quantity: 1,
        reference: "Door 2 row 1 position 4 - white lamp", rawText: "white indicator lamp", sourcePage: 4,
        boardNumber: "3918.24-12-1",
      },
    ],
  }, CATALOG, { fileName: "3918.24-12-1 MDB.pdf" });

  const selector = result.components.find((part) => part.partID === "allen-bradley-800f-selector");
  const lamps = result.components.find((part) => part.partID === "allen-bradley-800f-pilot-light");
  assert.equal(selector?.quantity, 2);
  assert.equal(lamps?.quantity, 3);
  assert.equal(result.unmatched.length, 1);
  assert.match(result.unmatched[0].reference, /Door 2 row 1 position 4/i);
});

test("Allen-Bradley door operators match by bulletin, device type, and common brand aliases", () => {
  const pushButton = matchCatalogPart(CATALOG, {
    manufacturer: "A-B", model: "800F-X10", type: "push-button switch",
  });
  const lamp = matchCatalogPart(CATALOG, {
    manufacturer: "Rockwell Automation", model: "800F-P16", type: "lamp",
  });
  const doorSwitch = matchCatalogPart(CATALOG, {
    manufacturer: "Allen Bradley", model: "802T-A1T", type: "limit switch",
  });

  assert.equal(pushButton?.id, "allen-bradley-800f-push-button");
  assert.equal(lamp?.id, "allen-bradley-800f-pilot-light");
  assert.equal(doorSwitch?.id, "allen-bradley-802t-door-switch");
});

test("the filename target excludes components belonging to a previous board", () => {
  assert.equal(targetBoardNumberFromFileName("3918.24-12-1 MDB.pdf"), "3918.24-12-1");
  assert.equal(targetBoardNumberFromFileName("Board_3918.24-12-1.pdf"), "3918.24-12-1");
  assert.equal(targetBoardNumberFromFileName("scheme-1.pdf"), "");
  const result = normalizeReading({
    board: { number: "3918.24-12-0", name: "Previous board" },
    pageBoards: [
      { page: 1, boardNumber: "3918.24-12-0" },
      { page: 2, boardNumber: "3918.24-12-1" },
    ],
    components: [
      { manufacturer: "ABB", model: "S201", type: "MCB", rating: "10A", poles: "1P", quantity: 8, reference: "QF1-QF8", sourcePage: 1, boardNumber: "" },
      { manufacturer: "ABB", model: "S202", type: "MCB", rating: "16A", poles: "2P", quantity: 2, reference: "QF20-QF21", sourcePage: 2, boardNumber: "3918.24-12-1" },
    ],
  }, CATALOG, { fileName: "3918.24-12-1 MDB.pdf" });

  assert.equal(result.board.number, "3918.24-12-1");
  assert.equal(result.board.name, "");
  assert.deepEqual(result.components.map((component) => component.partID), ["abb-s202-2p"]);
  assert.match(result.warnings.join(" "), /Ignored board 3918\.24-12-0/i);
  assert.match(result.warnings.join(" "), /Skipped component QF1-QF8/i);
});

test("a title-block contractor is not the board manufacturer and Tamhash evidence wins", () => {
  assert.equal(resolveBoardManufacturer({
    manufacturer: "כיתאו אליקטריק",
    manufacturerRole: "panel_builder",
    manufacturerCandidates: [],
  }), "");
  assert.equal(resolveBoardManufacturer({
    manufacturer: "כיתאו אליקטריק",
    manufacturerRole: "panel_builder",
    manufacturerCandidates: [{
      name: "תמח\"ש", role: "enclosure_manufacturer", evidence: "cabinet logo", sourcePage: 3,
    }],
  }), "Tamhash");

  const result = normalizeReading({
    board: {
      number: "3918.24-12-1",
      manufacturer: "כיתאו אליקטריק",
      manufacturerRole: "electrical_contractor",
      manufacturerCandidates: [
        { name: "כיתאו אליקטריק", role: "electrical_contractor", evidence: "title block", sourcePage: 1 },
        { name: "Tam Hash", role: "enclosure_manufacturer", evidence: "enclosure logo", sourcePage: 3 },
      ],
    },
    pageBoards: [], components: [], warnings: [],
  }, CATALOG, { fileName: "3918.24-12-1 MDB.pdf" });
  assert.equal(result.board.manufacturer, "Tamhash");
});

test("an inferred board type keeps its confidence and evidence for human verification", () => {
  const result = normalizeReading({
    board: {
      type: "MCC", typeConfidence: "Medium",
      typeEvidence: "Motor feeders with contactors and overload relays",
    },
    components: [],
  }, CATALOG);
  assert.equal(result.board.type, "MCC");
  assert.equal(result.board.typeConfidence, "medium");
  assert.match(result.board.typeEvidence, /motor feeders/i);
});

test("breaker shorthand is split into current, poles and curve", () => {
  assert.equal(ampereRating("ABB S201 C16"), "16A");
  assert.equal(breakerCurve("ABB S201 C16"), "C");
  assert.equal(ampereRating("FIRL 6A + N"), "6A");
  assert.equal(poleKey("FIRL 6A + N"), "1P+N");
  assert.equal(poleKey("3P + N"), "3P+N");
  assert.equal(poleKey("3P/4P"), "");
  assert.equal(poleKey("1P-4P"), "");
  assert.equal(ampereRating("breaking capacity 6kA"), "");
});

test("an ABB 6A plus neutral callout resolves to SN201 and keeps 6A", () => {
  const result = normalizeReading({
    board: {},
    components: [{
      manufacturer: "ABB", model: "FIRL", type: "MCB", rating: "6A + N",
      quantity: 4, reference: "QF1-QF4", rawText: "FIRL 6A + N",
    }],
  }, CATALOG);

  assert.equal(result.components.length, 1);
  assert.equal(result.components[0].partID, "abb-sn201-1pn");
  assert.equal(result.components[0].rating, "6A");
  assert.equal(result.components[0].poles, "1P+N");
});

test("recurring component lines are consolidated once across all pages", () => {
  const result = normalizeReading({
    board: {},
    components: [
      { manufacturer: "ABB", model: "SN201", type: "MCB", rating: "6A", poles: "1P+N", quantity: 2, reference: "QF1-QF2", sourcePage: 2 },
      { manufacturer: "ABB", model: "SN201", type: "MCB", rating: "6A", poles: "1P+N", quantity: 2, reference: "QF1-QF2", sourcePage: 5 },
      { manufacturer: "ABB", model: "SN201", type: "MCB", rating: "6A", poles: "1P+N", quantity: 1, reference: "QF3", sourcePage: 7 },
    ],
  }, CATALOG);

  assert.equal(result.components.length, 1);
  assert.equal(result.components[0].quantity, 3);
  assert.equal(result.components[0].reference, "QF1-QF2, QF3");
  assert.equal(result.components[0].sourcePage, 2);
});

test("S203 63A page rows become one document total without double-counting repeated references", () => {
  const result = normalizeReading({
    board: {},
    components: [
      { manufacturer: "ABB", model: "S203", type: "MCB", rating: "63A", poles: "", curve: "C", quantity: 2, reference: "QF1-QF2", sourcePage: 2 },
      { manufacturer: "ABB", model: "S203", type: "MCB", rating: "C63", poles: "3P", curve: "", quantity: 3, reference: "QF3-QF5", sourcePage: 6 },
      { manufacturer: "ABB", model: "S203", type: "MCB", rating: "63 A", poles: "3P", curve: "C", quantity: 2, reference: "QF1-QF2", sourcePage: 9 },
    ],
  }, CATALOG);

  assert.equal(result.components.length, 1);
  assert.equal(result.components[0].partID, "abb-s203-3p");
  assert.equal(result.components[0].rating, "63A");
  assert.equal(result.components[0].poles, "3P");
  assert.equal(result.components[0].curve, "C");
  assert.equal(result.components[0].quantity, 5);
  assert.equal(result.components[0].sourcePage, 2);
});

test("an exact scanned ampere chooses the matching catalog variant", () => {
  const variants = [
    { id: "breaker-125", manufacturer: "ABB", model: "XT1", type: "MCCB", rating: "125A", poles: "3P" },
    { id: "breaker-160", manufacturer: "ABB", model: "XT1", type: "MCCB", rating: "160A", poles: "3P" },
  ];
  const hit = matchCatalogPart(variants, {
    manufacturer: "ABB", model: "XT1", type: "MCCB", rating: "160 A", poles: "3P",
  });
  assert.equal(hit.id, "breaker-160");
});

test("the extracted main breaker is present in components with its ampere", () => {
  const mainCatalog = [
    { id: "abb-tmax-xt1", manufacturer: "ABB", model: "SACE Tmax XT1", type: "MCCB", rating: "IEC 160A frame", poles: "3P/4P" },
  ];
  const result = normalizeReading({
    board: {
      mainBreakerType: "MCCB",
      mainBreakerModel: "SACE Tmax XT1",
      mainBreakerAmpere: "160 A",
    },
    components: [],
  }, mainCatalog);

  assert.equal(result.board.mainBreakerAmpere, "160A");
  assert.equal(result.components.length, 1);
  assert.equal(result.components[0].partID, "abb-tmax-xt1");
  assert.equal(result.components[0].rating, "160A");
  assert.equal(result.components[0].quantity, 1);
  assert.equal(result.components[0].reference, "Main incomer");
});

test("the installed main-breaker callout corrects a conflicting board-level OCR current", () => {
  const result = normalizeReading({
    board: {
      mainBreakerType: "MCCB",
      mainBreakerModel: "SACE Tmax XT1",
      mainBreakerAmpere: "128A",
    },
    components: [{
      manufacturer: "ABB", model: "SACE Tmax XT1", type: "MCCB", rating: "160A",
      quantity: 1, reference: "Main incomer Q0", rawText: "Q0 XT1 160A", isMainBreaker: true,
    }],
  }, [{ id: "abb-tmax-xt1", manufacturer: "ABB", model: "SACE Tmax XT1", type: "MCCB", rating: "IEC 160A frame", poles: "3P/4P" }]);

  assert.equal(result.board.mainBreakerAmpere, "160A");
  assert.equal(result.components.length, 1);
  assert.equal(result.components[0].rating, "160A");
  assert.match(result.warnings.join(" "), /corrected from 128A to 160A/i);
});

test("the document response JSON Schema includes extraction constraints", () => {
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
  assert.equal(result.unmatched[0].manufacturer, "Nobody");
  assert.equal(result.unmatched[0].model, "ZX9000");
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
