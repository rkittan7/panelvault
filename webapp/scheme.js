// Reading an AutoCAD board scheme: what to ask Gemini for, and how to turn
// what comes back into something PanelVault can put on a board.
//
// Kept out of server.js so the extraction and matching rules can be tested
// directly. The production prompt lives as a reviewable text file instead of
// being buried in a JavaScript string.
const fs = require("node:fs");
const path = require("node:path");

const BOARD_SCHEME_INSTRUCTION = fs.readFileSync(
  path.join(__dirname, "prompts", "scheme-extract.txt"),
  "utf8",
).trim();

/** The exact shape the phone decodes. */
const BOARD_SCHEME_SCHEMA = {
  type: "object",
  required: ["board", "components", "warnings"],
  properties: {
    board: {
      type: "object",
      required: [
        "number", "name", "customer", "project", "type", "manufacturer",
        "mainBreakerType", "mainBreakerModel", "mainBreakerAmpere", "cabinetCount",
        "jobNumber", "revision", "supplyVoltage", "frequency", "earthingSystem",
        "ipRating", "formSeparation", "enclosureSize", "standards", "notes",
      ],
      properties: {
        number: { type: "string", description: "Exact board/drawing number from the relevant title block." },
        name: { type: "string", description: "Board name or description, separate from the project name." },
        customer: { type: "string", description: "Customer or client explicitly named on the drawing." },
        project: { type: "string", description: "Project, site or building name, separate from customer." },
        type: { type: "string", description: "Printed board classification such as MDB, SMDB, MCC or ATS." },
        manufacturer: { type: "string", description: "Board/enclosure manufacturer only when explicitly stated." },
        mainBreakerType: { type: "string", description: "Main incomer type, such as MCCB, ACB, MCB or isolator." },
        mainBreakerModel: { type: "string", description: "Exact manufacturer/model printed for the main incomer." },
        mainBreakerAmpere: { type: "string", description: "Main incomer current rating including unit." },
        cabinetCount: { type: "integer", minimum: 0, maximum: 40, description: "Physical cabinets or sections; 0 when unstated." },
        jobNumber: { type: "string", description: "Job or order number exactly as printed." },
        revision: { type: "string", description: "Drawing revision/state exactly as printed." },
        supplyVoltage: { type: "string", description: "Supply voltage exactly as printed." },
        frequency: { type: "string", description: "Supply frequency exactly as printed." },
        earthingSystem: { type: "string", description: "Earthing system exactly as printed, e.g. TN-S or TN-C-S." },
        ipRating: { type: "string", description: "Enclosure IP rating exactly as printed." },
        formSeparation: { type: "string", description: "Internal separation form exactly as printed." },
        enclosureSize: { type: "string", description: "Enclosure dimensions exactly as printed." },
        standards: { type: "array", maxItems: 20, items: { type: "string" }, description: "Standards explicitly printed for this board." },
        notes: { type: "string", description: "Board-specific construction/review notes; no generic prose." },
      },
    },
    components: {
      type: "array",
      maxItems: 200,
      description: "Every distinct component schedule/BOM line for the selected board.",
      items: {
        type: "object",
        required: [
          "rawText", "manufacturer", "model", "type", "rating", "poles",
          "curve", "sensitivity", "quantity", "reference", "sourcePage",
        ],
        properties: {
          rawText: { type: "string", description: "Identifying schedule row transcribed from the source." },
          manufacturer: { type: "string", description: "Manufacturer exactly as printed; empty when absent." },
          model: { type: "string", description: "Model/series exactly as printed, preserving significant suffixes." },
          type: { type: "string", description: "Printed device type such as MCB, MCCB, contactor or meter." },
          rating: { type: "string", description: "Current/power/voltage rating exactly as printed." },
          poles: { type: "string", description: "Pole count exactly as printed." },
          curve: { type: "string", description: "Trip curve/class exactly as printed." },
          sensitivity: { type: "string", description: "RCD sensitivity exactly as printed." },
          quantity: { type: "integer", minimum: 0, maximum: 999, description: "Explicit quantity or tag count; 0 when unknown." },
          reference: { type: "string", description: "Exact device tag(s), circuit or schedule reference." },
          sourcePage: { type: "integer", minimum: 0, description: "One-based PDF page for this line; 0 when unknown." },
        },
      },
    },
    warnings: {
      type: "array",
      maxItems: 20,
      items: { type: "string" },
      description: "Unreadable, ambiguous, conflicting or multi-board issues a reviewer must check.",
    },
  },
};

function boardSchemePrompt(fileName) {
  const named = String(fileName || "").trim();
  const responseShape = {
    board: {
      number: "", name: "", customer: "", project: "", type: "", manufacturer: "",
      mainBreakerType: "", mainBreakerModel: "", mainBreakerAmpere: "", cabinetCount: 0,
      jobNumber: "", revision: "", supplyVoltage: "", frequency: "", earthingSystem: "",
      ipRating: "", formSeparation: "", enclosureSize: "", standards: [], notes: "",
    },
    components: [{
      rawText: "", manufacturer: "", model: "", type: "", rating: "", poles: "",
      curve: "", sensitivity: "", quantity: 0, reference: "", sourcePage: 0,
    }],
    warnings: [],
  };
  return [
    "Read the complete electrical board document and extract the relevant title block,",
    "main incomer and every component schedule/BOM line.",
    named ? `The upload filename is "${named.slice(0, 200)}". Use it only to select the matching board or confirm an exact board number; do not derive other fields from it.` : "",
    "Return empty strings, empty arrays or 0 for information that is not visibly stated.",
    `Return one JSON object with exactly this shape (the components array may be empty): ${JSON.stringify(responseShape)}`,
  ].filter(Boolean).join(" ");
}

/** Normalised text used to compare a read part against the catalog. */
function partKey(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, "");
}

/** Comparable model keys, including only conservative notation reductions.
 * Catalog rows name product families ("SACE Tmax XT1") while schedules often
 * print a variant ("XT1D"). These reductions find the family without erasing
 * the exact raw line that the reviewer still needs to verify. */
function modelKeys(value) {
  const raw = partKey(value);
  if (!raw) return [];
  const keys = new Set([raw]);
  let withoutRangeWords = raw;
  for (const prefix of ["acti9", "sace", "tmax", "sentron"]) {
    if (withoutRangeWords.startsWith(prefix)) withoutRangeWords = withoutRangeWords.slice(prefix.length);
  }
  if (withoutRangeWords) keys.add(withoutRangeWords);
  if (/^s20[1-4]m$/.test(withoutRangeWords)) keys.add(withoutRangeWords.slice(0, -1));
  const tmaxVariant = withoutRangeWords.match(/^(xt[1-7])[cdn]$/);
  if (tmaxVariant) keys.add(tmaxVariant[1]);
  if (/^f20[1-4]a$/.test(withoutRangeWords)) keys.add("f200");
  return [...keys].filter((key) => key.length >= 3);
}

/** Best catalog part for something read off a drawing, or null.
 *
 * Deliberately conservative: a wrong match silently puts the wrong part on a
 * board and eventually into a stock count, which is worse than handing the
 * line back for a person to place. So the model has to agree, the brand has to
 * agree whenever the drawing names one, and an ambiguous tie is refused.
 */
function matchCatalogPart(catalog, part) {
  const models = modelKeys(part.model || part.rawText);
  if (!models.length) return null;
  const manufacturer = partKey(part.manufacturer);

  const scored = catalog
    .map((candidate) => {
      const candidateModels = modelKeys(candidate.model);
      if (!candidateModels.length) return null;

      let score = 0;
      for (const model of models) {
        for (const candidateModel of candidateModels) {
          if (candidateModel === model) score = Math.max(score, 3);
          else if (candidateModel.includes(model) || model.includes(candidateModel)) score = Math.max(score, 2);
        }
      }
      if (!score) return null;

      // A model alone is ambiguous across brands — several ranges share
      // numbers — so the brand must agree whenever the drawing names one.
      if (manufacturer) {
        const candidateManufacturer = partKey(candidate.manufacturer);
        if (candidateManufacturer !== manufacturer
          && !candidateManufacturer.includes(manufacturer)
          && !manufacturer.includes(candidateManufacturer)) return null;
        score += 1;
      }
      if (part.type && partKey(part.type) === partKey(candidate.type)) score += 1;
      return { candidate, score };
    })
    .filter(Boolean)
    .sort((a, b) => b.score - a.score);

  if (!scored.length) return null;
  // A tie between two different parts is not a match; it is a question.
  if (scored.length > 1
    && scored[0].score === scored[1].score
    && scored[0].candidate.id !== scored[1].candidate.id) {
    return null;
  }
  return scored[0].candidate;
}

const text = (value, max) => String(value ?? "").trim().slice(0, max);

/** Turn a raw model reading into the payload the phone consumes.
 *
 * Every field is clamped here rather than trusted: this is model output, and
 * it reaches a board draft that a workshop builds from.
 */
function normalizeReading(reading, catalog) {
  const board = reading?.board || {};
  const parts = Array.isArray(reading?.components) ? reading.components : [];
  const warnings = (Array.isArray(reading?.warnings) ? reading.warnings : [])
    .map((warning) => text(warning, 240))
    .filter(Boolean)
    .slice(0, 20);

  const components = [];
  const unmatched = [];
  for (const part of parts.slice(0, 200)) {
    const quantity = Math.min(Math.max(Math.trunc(Number(part.quantity) || 1), 1), 999);
    const hit = matchCatalogPart(catalog, part);
    if (hit) {
      components.push({
        partID: hit.id,
        manufacturer: hit.manufacturer,
        model: hit.model,
        type: hit.type,
        quantity,
        reference: text(part.reference, 120),
        rawText: text(part.rawText, 400),
        rating: text(part.rating, 60),
        poles: text(part.poles, 30),
        curve: text(part.curve, 30),
        sensitivity: text(part.sensitivity, 30),
        sourcePage: Math.min(Math.max(Math.trunc(Number(part.sourcePage) || 0), 0), 1000),
      });
    } else {
      const description = text(part.rawText, 400) || [part.manufacturer, part.model, part.rating]
        .map((bit) => text(bit, 60)).filter(Boolean).join(" ");
      if (!description && !text(part.type, 60)) continue;
      unmatched.push({
        description: description.slice(0, 140),
        manufacturer: text(part.manufacturer, 60),
        model: text(part.model, 80),
        type: text(part.type, 60),
        quantity,
        reference: text(part.reference, 120),
        rawText: text(part.rawText, 400),
        rating: text(part.rating, 60),
        poles: text(part.poles, 30),
        curve: text(part.curve, 30),
        sensitivity: text(part.sensitivity, 30),
        sourcePage: Math.min(Math.max(Math.trunc(Number(part.sourcePage) || 0), 0), 1000),
      });
    }
  }

  return {
    board: {
      number: text(board.number, 60),
      name: text(board.name, 120),
      customer: text(board.customer, 120),
      project: text(board.project, 120),
      type: text(board.type, 60),
      manufacturer: text(board.manufacturer, 60),
      mainBreakerType: text(board.mainBreakerType, 40),
      mainBreakerModel: text(board.mainBreakerModel, 80),
      mainBreakerAmpere: text(board.mainBreakerAmpere, 20),
      cabinetCount: Math.min(Math.max(Math.trunc(Number(board.cabinetCount) || 1), 1), 40),
      jobNumber: text(board.jobNumber, 60),
      revision: text(board.revision, 60),
      supplyVoltage: text(board.supplyVoltage, 40),
      frequency: text(board.frequency, 30),
      earthingSystem: text(board.earthingSystem, 30),
      ipRating: text(board.ipRating, 30),
      formSeparation: text(board.formSeparation, 40),
      enclosureSize: text(board.enclosureSize, 80),
      standards: (Array.isArray(board.standards) ? board.standards : [])
        .map((standard) => text(standard, 80)).filter(Boolean).slice(0, 20),
      notes: text(board.notes, 600),
    },
    components,
    unmatched,
    warnings,
  };
}

module.exports = {
  BOARD_SCHEME_INSTRUCTION,
  BOARD_SCHEME_SCHEMA,
  boardSchemePrompt,
  matchCatalogPart,
  modelKeys,
  normalizeReading,
  partKey,
};
