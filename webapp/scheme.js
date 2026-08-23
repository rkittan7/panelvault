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
        manufacturer: { type: "string", description: "Board/enclosure manufacturer exactly as printed, including Tamhash, Yakir or Rittal; empty only when unstated." },
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
      description: "Distinct component specifications instantiated on the selected board schematic, grouped after counting unique physical device references.",
      items: {
        type: "object",
        required: [
          "rawText", "manufacturer", "model", "type", "rating", "poles",
          "curve", "sensitivity", "quantity", "reference", "sourcePage",
        ],
        properties: {
          rawText: { type: "string", description: "Representative schematic callout or device label transcribed from the source." },
          manufacturer: { type: "string", description: "Manufacturer exactly as printed; empty when absent." },
          model: { type: "string", description: "Model/series exactly as printed, preserving significant suffixes." },
          type: { type: "string", description: "Printed device type such as MCB, MCCB, contactor or meter." },
          rating: { type: "string", description: "Device current including A, separated from curve and poles; for example C16 or 6A + N must return 16A or 6A." },
          poles: { type: "string", description: "Pole count normalized from the device callout, for example 6A + N means 1P+N." },
          curve: { type: "string", description: "Trip curve/class exactly as printed; for example C16 means curve C." },
          sensitivity: { type: "string", description: "RCD sensitivity exactly as printed." },
          quantity: { type: "integer", minimum: 0, maximum: 999, description: "Count of unique physical schematic device references; 0 when it cannot be determined safely." },
          reference: { type: "string", description: "Exact unique device tag(s) included in the quantity." },
          sourcePage: { type: "integer", minimum: 0, description: "First one-based schematic page using this device group; 0 when unknown." },
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
    "main incomer and every component actually used across the schematic pages. Include the main incomer itself once in components.",
    "Count quantity from unique physical device references in the schematic, not from the final-page parts list.",
    "For every breaker, separate its current, poles and trip curve: C16 is rating 16A with curve C; 6A + N is rating 6A with poles 1P+N. Never confuse 6kA breaking capacity with a 6A current rating.",
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

/** Canonical current carried by a breaker callout. This deliberately requires
 * the A to follow the number directly, so 6kA breaking capacity is never
 * mistaken for a 6A trip rating. MCB shorthand such as C16 is accepted. */
function ampereRating(...values) {
  for (const value of values) {
    const source = String(value || "").toUpperCase();
    const explicit = source.match(/(?:^|[^A-Z0-9])(\d+(?:\.\d+)?)\s*A(?![A-Z])/);
    if (explicit) return `${Number(explicit[1])}A`;
  }
  for (const value of values) {
    const source = String(value || "").toUpperCase();
    const curveMarking = source.match(/(?:^|[^A-Z0-9])([BCD])\s*(\d{1,3})(?:\s*A)?(?:$|[^A-Z0-9])/);
    if (curveMarking) return `${Number(curveMarking[2])}A`;
  }
  return "";
}

function breakerCurve(...values) {
  for (const value of values) {
    const source = String(value || "").toUpperCase();
    const marking = source.match(/(?:^|[^A-Z0-9])([BCD])\s*\d{1,3}(?:\s*A)?(?:$|[^A-Z0-9])/);
    if (marking) return marking[1];
  }
  return "";
}

/** Fixed pole arrangement only. Catalog ranges such as 1P-4P intentionally do
 * not produce a key because they cannot identify one exact stocked family. */
function poleKey(...values) {
  for (const value of values) {
    const source = String(value || "").toUpperCase().replace(/\s+/g, "");
    if (/[1-4]P(?:\/|-)[1-4]P/.test(source)) continue;
    const phaseNeutral = source.match(/(?:^|[^0-9])([1-3])P?\+N(?:$|[^A-Z0-9])/);
    if (phaseNeutral) return `${phaseNeutral[1]}P+N`;
    if (/(?:\d+(?:\.\d+)?)A\+N(?:$|[^A-Z0-9])/.test(source)) return "1P+N";
    const fixed = source.match(/(?:^|[^0-9])([1-4])P(?:$|[^+A-Z0-9-])/);
    if (fixed) return `${fixed[1]}P`;
  }
  return "";
}

function typeKey(value) {
  const key = partKey(value);
  if (key === "mcb" || key.includes("miniaturecircuitbreaker")) return "mcb";
  if (key === "mccb" || key.includes("mouldedcasecircuitbreaker") || key.includes("moldedcasecircuitbreaker")) return "mccb";
  return key;
}

function exactAmpereRating(value) {
  const source = String(value || "").trim();
  return /^\d+(?:\.\d+)?\s*A$/i.test(source) ? ampereRating(source) : "";
}

function sameModel(left, right) {
  const leftKeys = modelKeys(left);
  const rightKeys = modelKeys(right);
  return leftKeys.some((key) => rightKeys.includes(key));
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
  const manufacturer = partKey(part.manufacturer);
  const requestedType = typeKey(part.type);
  const requestedPoles = poleKey(part.poles, part.rawText, part.rating);
  const requestedAmpere = ampereRating(part.rating, part.rawText);

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
      const modelMatched = score > 0;
      // A model alone is ambiguous across brands — several ranges share
      // numbers — so the brand must agree whenever the drawing names one.
      if (manufacturer) {
        const candidateManufacturer = partKey(candidate.manufacturer);
        if (candidateManufacturer !== manufacturer
          && !candidateManufacturer.includes(manufacturer)
          && !manufacturer.includes(candidateManufacturer)) return null;
        score += 1;
      }

      const candidateType = typeKey(candidate.type);
      const candidatePoles = poleKey(candidate.poles);
      const candidateAmpere = exactAmpereRating(candidate.rating);

      if (!modelMatched) {
        // A circuit/load label can occupy the model position in a schematic
        // callout (for example FIRL beside 6A + N). Match without a model only
        // when brand, device type and one fixed pole arrangement identify a
        // single catalog family; the tie check below still refuses ambiguity.
        if (!manufacturer || !requestedType || !requestedPoles) return null;
        if (candidateType !== requestedType || candidatePoles !== requestedPoles) return null;
        score += 2;
      }

      if (requestedType && requestedType === candidateType) score += 1;
      if (requestedPoles && candidatePoles) {
        if (requestedPoles !== candidatePoles) return null;
        score += 2;
      }
      if (requestedAmpere && candidateAmpere) {
        if (requestedAmpere !== candidateAmpere) return null;
        score += 3;
      }
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

function firstSourcePage(left, right) {
  const pages = [left, right].map((value) => Math.trunc(Number(value) || 0)).filter((value) => value > 0);
  return pages.length ? Math.min(...pages) : 0;
}

/** One exact specification appears once in the board. Gemini can still return
 * the same grouped line for multiple pages, so consolidate defensively. When
 * the reference text is identical it is the same physical devices and the
 * larger count wins; different reference groups are added together. */
function consolidateComponents(lines) {
  const consolidated = new Map();
  for (const line of Array.isArray(lines) ? lines : []) {
    const fallbackIdentity = line.partID || [
      line.manufacturer, line.model, line.type,
      line.description || (!line.model && !line.type ? line.rawText : ""),
    ].map(partKey).join("|");
    const key = [
      fallbackIdentity,
      partKey(line.rating),
      partKey(line.poles),
      partKey(line.curve),
      partKey(line.sensitivity),
    ].join("|");
    const existing = consolidated.get(key);
    if (!existing) {
      consolidated.set(key, { ...line });
      continue;
    }

    const existingReference = text(existing.reference, 120);
    const incomingReference = text(line.reference, 120);
    const sameReferences = Boolean(existingReference && incomingReference
      && partKey(existingReference) === partKey(incomingReference));
    const existingQuantity = Math.max(1, Math.trunc(Number(existing.quantity) || 1));
    const incomingQuantity = Math.max(1, Math.trunc(Number(line.quantity) || 1));
    existing.quantity = Math.min(9999, sameReferences
      ? Math.max(existingQuantity, incomingQuantity)
      : existingQuantity + incomingQuantity);
    if (incomingReference && !sameReferences) {
      existing.reference = [...new Set([existingReference, incomingReference].filter(Boolean))].join(", ").slice(0, 120);
    }
    existing.sourcePage = firstSourcePage(existing.sourcePage, line.sourcePage);
  }
  return [...consolidated.values()];
}

/** Turn a raw model reading into the payload the phone consumes.
 *
 * Every field is clamped here rather than trusted: this is model output, and
 * it reaches a board draft that a workshop builds from.
 */
function normalizeReading(reading, catalog) {
  const board = reading?.board || {};
  const parts = Array.isArray(reading?.components) ? [...reading.components] : [];
  const mainModel = text(board.mainBreakerModel, 80);
  const mainAmpere = ampereRating(board.mainBreakerAmpere);
  if (mainModel && !parts.some((part) => sameModel(part?.model || part?.rawText, mainModel))) {
    parts.unshift({
      rawText: [board.mainBreakerType, mainModel, mainAmpere].filter(Boolean).join(" "),
      manufacturer: "",
      model: mainModel,
      type: text(board.mainBreakerType, 60),
      rating: mainAmpere,
      poles: "",
      curve: "",
      sensitivity: "",
      quantity: 1,
      reference: "Main incomer",
      sourcePage: 0,
    });
  }
  const warnings = (Array.isArray(reading?.warnings) ? reading.warnings : [])
    .map((warning) => text(warning, 240))
    .filter(Boolean)
    .slice(0, 20);

  const components = [];
  const unmatched = [];
  for (const part of parts.slice(0, 200)) {
    const quantity = Math.min(Math.max(Math.trunc(Number(part.quantity) || 1), 1), 999);
    const isMain = mainModel && sameModel(part?.model || part?.rawText, mainModel)
      && (quantity === 1 || /main|incomer|incoming/i.test(String(part?.reference || "")));
    const detectedAmpere = ampereRating(part.rating, part.rawText) || (isMain ? mainAmpere : "");
    const detectedPoles = poleKey(part.poles, part.rawText, part.rating) || text(part.poles, 30);
    const detectedCurve = breakerCurve(part.curve, part.rating, part.rawText) || text(part.curve, 30);
    const normalizedPart = {
      ...part,
      rating: detectedAmpere || text(part.rating, 60),
      poles: detectedPoles,
      curve: detectedCurve,
    };
    const hit = matchCatalogPart(catalog, normalizedPart);
    if (hit) {
      components.push({
        partID: hit.id,
        manufacturer: hit.manufacturer,
        model: hit.model,
        type: hit.type,
        quantity,
        reference: text(part.reference, 120),
        rawText: text(part.rawText, 400),
        rating: text(normalizedPart.rating, 60),
        poles: text(normalizedPart.poles, 30),
        curve: text(normalizedPart.curve, 30),
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
        rating: text(normalizedPart.rating, 60),
        poles: text(normalizedPart.poles, 30),
        curve: text(normalizedPart.curve, 30),
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
      mainBreakerAmpere: mainAmpere || text(board.mainBreakerAmpere, 20),
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
    components: consolidateComponents(components),
    unmatched: consolidateComponents(unmatched),
    warnings,
  };
}

module.exports = {
  BOARD_SCHEME_INSTRUCTION,
  BOARD_SCHEME_SCHEMA,
  boardSchemePrompt,
  ampereRating,
  breakerCurve,
  consolidateComponents,
  matchCatalogPart,
  modelKeys,
  normalizeReading,
  partKey,
  poleKey,
};
