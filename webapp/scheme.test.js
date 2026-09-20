const assert = require("node:assert/strict");
const test = require("node:test");
const {
  BOARD_SCHEME_INSTRUCTION,
  houseDefaultPart,
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
  assert.match(BOARD_SCHEME_INSTRUCTION, /same board main once\s+in components/i);
  assert.match(BOARD_SCHEME_INSTRUCTION, /source -> device -> common-bus path/i);
  assert.match(BOARD_SCHEME_INSTRUCTION, /sectional mains downstream of the\s+common bus/i);
  assert.match(BOARD_SCHEME_INSTRUCTION, /never omit a visibly installed device/i);
  assert.match(BOARD_SCHEME_INSTRUCTION, /final coverage pass page by page/i);
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
  assert.match(boardSchemePrompt("3918.24-12-1 MDB.pdf"), /distinguish the one board_main device from UPS\/live\/essential section_main devices/i);
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

test("ABB MS116 matches its catalog family even when Gemini puts the order code in model", () => {
  const catalog = require("./catalog.json");
  const cases = [
    { manufacturer: "ABB", model: "MS116", type: "MPCB", poles: "3P" },
    { manufacturer: "ABB", model: "MS 116-16", type: "Manual motor starter", rating: "10-16A" },
    {
      manufacturer: "ABB",
      model: "1SAM250000R1011",
      type: "Motor protection circuit breaker",
      poles: "1P",
      rawText: "ABB MS116-16 10-16A 1SAM250000R1011",
    },
  ];
  for (const part of cases) {
    assert.equal(matchCatalogPart(catalog, part)?.id, "abb-ms116", JSON.stringify(part));
  }
});

/* A schematic labels a device by its circuit tag — QC200, KM3, -Q1 — and the
   model itself is printed beside the symbol or in the schedule. When the tag
   lands in the model field, matching it as a model finds nothing, and the line
   comes back for a person to place by hand. */
test("a circuit tag in the model position falls back to the model printed in the callout", () => {
  const catalog = [
    { id: "abb-af30", manufacturer: "ABB", model: "AF30", type: "Contactor", rating: "32A AC-3, 15kW", poles: "3P" },
    { id: "abb-af38", manufacturer: "ABB", model: "AF38", type: "Contactor", rating: "38A AC-3, 18.5kW", poles: "3P" },
  ];
  const cases = [
    { model: "QC200", rawText: "QC200 ABB AF38 38A AC-3" },
    { model: "QC200", rawText: "ABB AF38-30-00 contactor" },
    { model: "-KM3", rawText: "-KM3 / AF38 / 3P" },
  ];
  for (const { model, rawText } of cases) {
    const part = { manufacturer: "ABB", model, type: "Contactor", poles: "3P", reference: model, rawText };
    assert.equal(matchCatalogPart(catalog, part)?.id, "abb-af38", JSON.stringify(part));
  }
});

test("a tag with no model anywhere on the line is still handed back, not guessed", () => {
  const catalog = [
    { id: "abb-af30", manufacturer: "ABB", model: "AF30", type: "Contactor", rating: "32A AC-3, 15kW", poles: "3P" },
    { id: "abb-af38", manufacturer: "ABB", model: "AF38", type: "Contactor", rating: "38A AC-3, 18.5kW", poles: "3P" },
  ];
  const part = {
    manufacturer: "ABB", model: "QC200", type: "Contactor", poles: "3P",
    reference: "QC200", rawText: "QC200 pump starter",
  };
  assert.equal(matchCatalogPart(catalog, part), null);
});

test("a model printed in the callout still obeys the brand the drawing names", () => {
  const catalog = [
    { id: "abb-af38", manufacturer: "ABB", model: "AF38", type: "Contactor", rating: "38A AC-3, 18.5kW", poles: "3P" },
  ];
  const part = {
    manufacturer: "Siemens", model: "QC200", type: "Contactor", poles: "3P",
    reference: "QC200", rawText: "QC200 AF38 38A",
  };
  assert.equal(matchCatalogPart(catalog, part), null);
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

test("the source-side Socomec transfer switch outranks UPS and live field mains", () => {
  const catalog = require("./catalog.json");
  const result = normalizeReading({
    board: {
      number: "MDB-1",
      mainBreakerType: "MCCB",
      mainBreakerModel: "ABB SACE Tmax XT4",
      mainBreakerAmpere: "250A",
      mainBreakerReference: "QF-UPS",
      mainBreakerEvidence: "UTILITY + GENERATOR -> QS0 -> common bus",
    },
    components: [
      {
        manufacturer: "Socomec", model: "ATyS p", type: "Automatic Transfer Switch",
        rating: "630A", poles: "4P", quantity: 1, reference: "QS0",
        rawText: "UTILITY + GENERATOR -> QS0 SOCOMEC ATyS p -> COMMON BUS",
        sourcePage: 1, supplyRole: "board_main", isMainBreaker: true,
      },
      {
        manufacturer: "ABB", model: "SACE Tmax XT4", type: "MCCB",
        rating: "250A", poles: "4P", quantity: 1, reference: "QF-UPS",
        rawText: "UPS FIELD MAIN", sourcePage: 2, supplyRole: "section_main", isMainBreaker: false,
      },
      {
        manufacturer: "ABB", model: "SACE Tmax XT4", type: "MCCB",
        rating: "250A", poles: "4P", quantity: 1, reference: "QF-LIVE",
        rawText: "LIVE FIELD MAIN", sourcePage: 3, supplyRole: "section_main", isMainBreaker: false,
      },
    ],
  }, catalog);

  assert.equal(result.board.mainBreakerType, "Changeover Switch");
  assert.equal(result.board.mainBreakerModel, "Socomec ATyS p");
  assert.equal(result.board.mainBreakerAmpere, "630A");
  assert.equal(result.board.mainBreakerReference, "QS0");
  assert.equal(result.board.mainBreakerEvidence, "UTILITY + GENERATOR -> QS0 -> common bus");
  assert.equal(result.components.find((part) => part.partID === "socomec-atys-p")?.quantity, 1);
  assert.equal(result.components.filter((part) => part.partID === "abb-tmax-xt4").length, 1);
  assert.match(result.warnings.join(" "), /corrected from ABB SACE Tmax XT4 to Socomec ATyS p/i);
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
    { id: "abb-f202", manufacturer: "ABB", model: "F202", type: "RCCB" },
    { id: "abb-f204", manufacturer: "ABB", model: "F204", type: "RCCB" },
  ];
  assert.ok(modelKeys("SACE Tmax XT1").includes("xt1"));
  assert.equal(matchCatalogPart(extendedCatalog, { manufacturer: "ABB", model: "XT1D" }).id, "abb-tmax-xt1");
  // F200 is two rows now: the printed pole count picks the family, and the
  // four-pole drawing must not land on the two-pole part.
  assert.equal(matchCatalogPart(extendedCatalog, { manufacturer: "ABB", model: "F204A" }).id, "abb-f204");
  assert.equal(matchCatalogPart(extendedCatalog, { manufacturer: "ABB", model: "F202A" }).id, "abb-f202");
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

test("door inventory and schematic inventory each retain their full response allowance", () => {
  const rows = (prefix, count, sourcePage) => Array.from({ length: count }, (_, index) => ({
    manufacturer: "Unknown",
    model: `${prefix}-${index + 1}`,
    type: "Accessory",
    quantity: 1,
    reference: `${prefix}${index + 1}`,
    rawText: `${prefix} device ${index + 1}`,
    sourcePage,
  }));
  const result = normalizeReading({
    board: {},
    doorDevices: rows("DOOR", 120, 2),
    components: rows("SCHEMATIC", 120, 3),
  }, CATALOG);

  assert.equal(result.components.length, 0);
  assert.equal(result.unmatched.length, 240);
  assert.ok(result.unmatched.some((part) => part.model === "DOOR-120"));
  assert.ok(result.unmatched.some((part) => part.model === "SCHEMATIC-120"));
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

const LAMP_CATALOG = [
  { id: "allen-bradley-800f-pilot-light", manufacturer: "Allen-Bradley", model: "800F pilot light", type: "Pilot Light", rating: "22.5mm" },
  { id: "allen-bradley-800fp-pilot-light-red", manufacturer: "Allen-Bradley", model: "800FP pilot light, red", type: "Pilot Light", rating: "22.5mm" },
  { id: "allen-bradley-800fp-pilot-light-green", manufacturer: "Allen-Bradley", model: "800FP pilot light, green", type: "Pilot Light", rating: "22.5mm" },
  { id: "eaton-m22-pilot-light-red", manufacturer: "Eaton", model: "M22 pilot light, red", type: "Pilot Light", rating: "22.5mm" },
  { id: "eaton-m22-pilot-light-green", manufacturer: "Eaton", model: "M22 pilot light, green", type: "Pilot Light", rating: "22.5mm" },
  { id: "satec-pm130e-plus", manufacturer: "Satec", model: "PM130E PLUS", type: "Meter", rating: "230/400V" },
  { id: "satec-pm130eh-plus", manufacturer: "Satec", model: "PM130EH PLUS", type: "Meter", rating: "230/400V" },
];

test("the metal 800F is not mistaken for the plastic 800FP", () => {
  for (const part of [
    { manufacturer: "Allen-Bradley", model: "800F pilot light", type: "Pilot Light" },
    { manufacturer: "Allen-Bradley", model: "800F", type: "Pilot Light", curve: "Red" },
  ]) {
    assert.equal(matchCatalogPart(LAMP_CATALOG, part)?.id, "allen-bradley-800f-pilot-light", JSON.stringify(part));
  }
  assert.deepEqual(modelKeys("800FP pilot light, red").includes("800fp"), true);
  assert.deepEqual(modelKeys("800F pilot light").includes("800fp"), false);
});

test("a lamp split by lens colour is found by the colour the drawing gives", () => {
  const green = matchCatalogPart(LAMP_CATALOG, { manufacturer: "Allen-Bradley", model: "800FP", type: "Pilot Light", curve: "Green" });
  assert.equal(green?.id, "allen-bradley-800fp-pilot-light-green");
  const hebrew = matchCatalogPart(LAMP_CATALOG, { manufacturer: "Eaton", model: "M22", type: "Pilot Light", rawText: "נורית סימון אדומה" });
  assert.equal(hebrew?.id, "eaton-m22-pilot-light-red");
});

test("a lamp with no single colour on the drawing is left for a person", () => {
  for (const rawText of ["", "red / green", "reduced glare"]) {
    assert.equal(matchCatalogPart(LAMP_CATALOG, { manufacturer: "Eaton", model: "M22", type: "Pilot Light", rawText }), null, rawText);
  }
});

test("Moeller on a drawing is Eaton", () => {
  const hit = matchCatalogPart(LAMP_CATALOG, { manufacturer: "Moeller", model: "M22", type: "Pilot Light", curve: "green" });
  assert.equal(hit?.id, "eaton-m22-pilot-light-green");
});

test("a SATEC variant printed without PLUS still finds its own row", () => {
  const hit = matchCatalogPart(LAMP_CATALOG, { manufacturer: "SATEC", model: "PM130E", type: "Meter" });
  assert.equal(hit?.id, "satec-pm130e-plus");
});

const HOUSE_CATALOG = LAMP_CATALOG.concat([
  { id: "salzer-sz22-red", manufacturer: "Salzer", model: "SZ22 LED pilot lamp, red", type: "Indicator Light", rating: "24-240V", poles: "22mm" },
  { id: "salzer-sz22-green", manufacturer: "Salzer", model: "SZ22 LED pilot lamp, green", type: "Indicator Light", rating: "24-240V", poles: "22mm" },
  { id: "salzer-pl16-22d-red", manufacturer: "Salzer", model: "PL16-22D LED indicator, red", type: "Indicator Light", rating: "6-380V", poles: "22mm" },
]);

test("a lamp with no brand printed is the house lamp in the colour shown", () => {
  const onCurve = matchCatalogPart(HOUSE_CATALOG, { manufacturer: "", model: "", type: "Pilot Light", curve: "red" });
  assert.equal(onCurve?.id, "salzer-sz22-red");
  // The colour is often only in the position label, not a variant field.
  const onReference = matchCatalogPart(HOUSE_CATALOG, {
    manufacturer: "", model: "", type: "Indicator Lamp", reference: "Door 2 row 1 position 4 - green RUN lamp",
  });
  assert.equal(onReference?.id, "salzer-sz22-green");
});

test("the house lamp is never assumed over something the drawing actually says", () => {
  // A brand is printed: not ours to assume.
  assert.equal(houseDefaultPart(HOUSE_CATALOG, { manufacturer: "Eaton", type: "Pilot Light", curve: "red" }), null);
  // A model is printed but unmatched: a question for a person, not an assumption.
  assert.equal(houseDefaultPart(HOUSE_CATALOG, { manufacturer: "", model: "XB7EV04BP", type: "Pilot Light", curve: "red" }), null);
  // No colour: which part to order is still unknown, so it stays in review.
  assert.equal(houseDefaultPart(HOUSE_CATALOG, { manufacturer: "", model: "", type: "Pilot Light", curve: "" }), null);
  // Not a lamp.
  assert.equal(houseDefaultPart(HOUSE_CATALOG, { manufacturer: "", model: "", type: "Push Button", curve: "red" }), null);
});

test("an unbranded lamp is left alone when the house lamp is not in the catalog", () => {
  const withoutSalzer = HOUSE_CATALOG.filter((part) => !part.id.startsWith("salzer-sz22"));
  assert.equal(matchCatalogPart(withoutSalzer, { manufacturer: "", model: "", type: "Pilot Light", curve: "red" }), null);
});

test("the prompt asks for a lamp colour without inventing one", () => {
  assert.match(BOARD_SCHEME_INSTRUCTION, /lens color is stock-defining/);
  assert.match(boardSchemePrompt("board.pdf"), /lens colour is stock-defining/);
});

// The real catalog, so a Hager reference is proven to reach its row among
// every other brand's models, not just in a hand-picked list.
const FULL_CATALOG = require("./catalog.json");

test("a printed Hager order reference finds its catalog family", () => {
  const cases = [
    [{ manufacturer: "HAGER", model: "EPN524", type: "Impulse relay" }, "hager-epn"],
    [{ manufacturer: "Hager", model: "EPN 510", type: "Teleruptor" }, "hager-epn"],
    [{ manufacturer: "", model: "EPN546", type: "Relay" }, "hager-epn"],
    [{ manufacturer: "HAGER", model: "EPS450B", type: "" }, "hager-eps"],
    [{ manufacturer: "", model: "EPS410B", type: "" }, "hager-eps"],
    [{ manufacturer: "HAGER", model: "60060", type: "Load shedder" }, "hager-load-shed"],
    [{ manufacturer: "HAGER", model: "ED183", type: "" }, "hager-load-shed"],
    [{ manufacturer: "HAGER", model: "EZM100", type: "Time relay" }, "hager-ezm100"],
    [{ manufacturer: "", model: "EZD100", type: "Timer" }, "hager-ezd100"],
    [{ manufacturer: "HAGER", model: "EZF100", type: "" }, "hager-ezf100"],
    [{ manufacturer: "HAGER", model: "EZL100", type: "" }, "hager-ezl100"],
    [{ manufacturer: "HAGER", model: "EMN001", type: "Staircase timer" }, "hager-emn001"],
    [{ manufacturer: "HAGER", model: "EEN101", type: "Photocell" }, "hager-een100"],
    [{ manufacturer: "", model: "EEN100", type: "Twilight switch" }, "hager-een100"],
  ];
  for (const [part, id] of cases) {
    assert.equal(matchCatalogPart(FULL_CATALOG, part)?.id, id, `${part.model} should be ${id}`);
  }
});

test("Hager accessories and other brands are not read as Hager devices", () => {
  // A spare cell and a latching-relay add-on are accessories, not the device.
  assert.equal(matchCatalogPart(FULL_CATALOG, { manufacturer: "HAGER", model: "EEN002" }), null);
  assert.equal(matchCatalogPart(FULL_CATALOG, { manufacturer: "HAGER", model: "EPN051" }), null);
  assert.ok(!modelKeys("EEN003").includes("hagereen"));
  // A Hager reference printed under another brand is a question, not a match.
  assert.equal(matchCatalogPart(FULL_CATALOG, { manufacturer: "ABB", model: "EPN524" }), null);
  // "een" sits inside "green": the Hager key must not reach a green lamp.
  assert.equal(
    matchCatalogPart(FULL_CATALOG, { manufacturer: "Salzer", model: "SZ22", type: "Pilot light", curve: "green" })?.id,
    "salzer-sz22-green",
  );
});

test("every catalog row still finds itself by brand and model", () => {
  const lost = FULL_CATALOG
    .filter((row) => matchCatalogPart(FULL_CATALOG, { manufacturer: row.manufacturer, model: row.model, type: row.type })?.id !== row.id)
    .map((row) => row.id);
  const hagerLost = lost.filter((id) => id.startsWith("hager-"));
  assert.deepEqual(hagerLost, []);
});

test("the prompt asks for Hager's printed order reference", () => {
  assert.match(BOARD_SCHEME_INSTRUCTION, /Hager modular devices print a full order reference/);
});
