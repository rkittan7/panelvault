// Reading an AutoCAD board scheme: what to ask Gemini for, and how to turn
// what comes back into something PanelVault can put on a board.
//
// Kept out of server.js so the matching rules can be tested directly. Nothing
// here talks to the network or touches stored data.

const BOARD_SCHEME_INSTRUCTION = [
  "You read single-line and panel-layout drawings exported from AutoCAD for",
  "electrical distribution boards, and return what is actually printed on them.",
  "",
  "Rules you must follow:",
  "- Report only what the drawing states. Leave a field empty rather than",
  "  inferring it. An empty field is corrected in seconds; a confident wrong",
  "  one gets built into a real panel.",
  "- Read the component schedule or bill of materials if the drawing has one.",
  "  That table, not the symbols, is the reliable source of quantities.",
  "- Quantities are per board. If the drawing covers several boards, report the",
  "  one the title block names.",
  "- Keep manufacturer and model exactly as printed (\"iC60N\", not \"IC60\").",
  "- Amperages include the unit, as in \"630A\".",
].join("\n");

/** The exact shape the phone decodes. */
const BOARD_SCHEME_SCHEMA = {
  type: "object",
  properties: {
    board: {
      type: "object",
      properties: {
        number: { type: "string", description: "Board number from the title block, e.g. 3918.24-1" },
        name: { type: "string", description: "Board name or description, e.g. Main Distribution Board" },
        customer: { type: "string", description: "Customer or client named on the drawing" },
        project: { type: "string", description: "Project or site name" },
        type: { type: "string", description: "MDB, SDB, MCC, ATS, Lighting, Control, or similar" },
        manufacturer: { type: "string", description: "Enclosure manufacturer if stated" },
        mainBreakerType: { type: "string", description: "MCCB, ACB, MCB or Main Breaker" },
        mainBreakerModel: { type: "string", description: "Main incomer manufacturer and model" },
        mainBreakerAmpere: { type: "string", description: "Main incomer rating with unit, e.g. 630A" },
        cabinetCount: { type: "integer", description: "Number of cabinets or sections" },
        notes: { type: "string", description: "Anything an electrician should check before building" },
      },
    },
    components: {
      type: "array",
      description: "Every part in the schedule, one entry per line.",
      items: {
        type: "object",
        properties: {
          manufacturer: { type: "string" },
          model: { type: "string" },
          type: { type: "string", description: "MCB, MCCB, RCBO, Contactor, VFD, and so on" },
          rating: { type: "string" },
          poles: { type: "string" },
          quantity: { type: "integer" },
          reference: { type: "string", description: "Circuit or tag reference, e.g. Q3" },
        },
      },
    },
  },
};

function boardSchemePrompt(fileName) {
  const named = String(fileName || "").trim();
  return [
    "Read this electrical distribution board scheme and return its details and",
    "its component schedule.",
    named ? `The file is named "${named.slice(0, 200)}", which may carry the board number.` : "",
    "If a field is not printed on the drawing, return an empty string for it.",
  ].filter(Boolean).join(" ");
}

/** Normalised text used to compare a read part against the catalog. */
function partKey(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, "");
}

/** Best catalog part for something read off a drawing, or null.
 *
 * Deliberately conservative: a wrong match silently puts the wrong part on a
 * board and eventually into a stock count, which is worse than handing the
 * line back for a person to place. So the model has to agree, the brand has to
 * agree whenever the drawing names one, and an ambiguous tie is refused.
 */
function matchCatalogPart(catalog, part) {
  const model = partKey(part.model);
  if (!model || model.length < 3) return null;
  const manufacturer = partKey(part.manufacturer);

  const scored = catalog
    .map((candidate) => {
      const candidateModel = partKey(candidate.model);
      if (!candidateModel) return null;

      let score = 0;
      if (candidateModel === model) score = 3;
      else if (candidateModel.includes(model) || model.includes(candidateModel)) score = 2;
      else return null;

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
        reference: text(part.reference, 60),
      });
    } else {
      const description = [part.manufacturer, part.model, part.rating]
        .map((bit) => text(bit, 60)).filter(Boolean).join(" ");
      if (!description && !text(part.type, 60)) continue;
      unmatched.push({
        description: description.slice(0, 140),
        type: text(part.type, 60),
        quantity,
        reference: text(part.reference, 60),
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
      notes: text(board.notes, 600),
    },
    components,
    unmatched,
  };
}

module.exports = {
  BOARD_SCHEME_INSTRUCTION,
  BOARD_SCHEME_SCHEMA,
  boardSchemePrompt,
  matchCatalogPart,
  normalizeReading,
  partKey,
};
