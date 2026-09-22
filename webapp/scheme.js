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

const BOARD_MANUFACTURERS = [
  "Generic", "Rittal", "ABB", "Yakir", "Tamhash", "HAGER", "Delta",
  "Schneider", "Siemens", "Eaton", "Legrand", "Mean Well", "Phoenix",
  "Danfoss", "Socomec",
];

function identityKey(value) {
  return String(value || "").normalize("NFKD").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "");
}

function canonicalBoardManufacturer(value) {
  const key = identityKey(value);
  if (!key) return "";
  if (["tamhash", "tamash", "תמחש"].includes(key)) return "Tamhash";
  const exact = BOARD_MANUFACTURERS.find((name) => identityKey(name) === key);
  if (exact) return exact;
  // Data tables print the maker with its product line: "פח-תמחש T4P-M".
  // Accept a known name inside a longer label, never a fragment of one.
  if (["tamhash", "tamash", "תמחש"].some((alias) => key.includes(alias))) return "Tamhash";
  return BOARD_MANUFACTURERS.find((name) => identityKey(name).length >= 4 && key.includes(identityKey(name))) || "";
}

function enclosureManufacturerRole(value) {
  return /enclosure|cabinet|board[ _-]*manufacturer/i.test(String(value || ""));
}

function resolveBoardManufacturer(board) {
  const candidates = Array.isArray(board?.manufacturerCandidates) ? board.manufacturerCandidates : [];
  for (const candidate of candidates) {
    if (!enclosureManufacturerRole(candidate?.role)) continue;
    const known = canonicalBoardManufacturer(candidate?.name);
    if (known) return known;
  }
  const known = canonicalBoardManufacturer(board?.manufacturer);
  if (known) return known;
  if (enclosureManufacturerRole(board?.manufacturerRole)) return String(board.manufacturer || "").trim();
  // Backward compatibility for readings made before manufacturer roles were
  // requested. New readings always carry manufacturerRole and therefore do
  // not promote a contractor/title-block company into this field.
  return board?.manufacturerRole == null ? String(board?.manufacturer || "").trim() : "";
}

function boardNumberKey(value) {
  return String(value || "").toUpperCase().replace(/[^A-Z0-9]+/g, "");
}

/** A filename is a hard selector only when it contains a structured identifier
 * with at least two separators, e.g. 3918.24-12-1. Generic filenames such as
 * scheme-1.pdf are deliberately not trusted as board numbers. */
function targetBoardNumberFromFileName(value) {
  const base = String(value || "").replace(/\\/g, "/").split("/").pop().replace(/\.[^.]+$/, "");
  const numericCandidates = base.match(/\d+(?:[._/-][A-Za-z0-9]+){2,}/g) || [];
  const candidates = numericCandidates.length
    ? numericCandidates
    : base.match(/[A-Za-z0-9]+(?:[._/-][A-Za-z0-9]+){2,}/g) || [];
  return candidates
    .filter((candidate) => /\d/.test(candidate))
    .sort((left, right) => {
      const leftSeparators = (left.match(/[._/-]/g) || []).length;
      const rightSeparators = (right.match(/[._/-]/g) || []).length;
      return rightSeparators - leftSeparators || right.length - left.length;
    })[0] || "";
}

/** The exact shape the phone decodes. */
const BOARD_SCHEME_SCHEMA = {
  type: "object",
  required: ["board", "pageBoards", "components", "doorDevices", "warnings"],
  properties: {
    board: {
      type: "object",
      required: [
        "number", "name", "customer", "project", "type", "typeConfidence", "typeEvidence", "manufacturer",
        "manufacturerRole", "manufacturerEvidence", "manufacturerCandidates",
        "mainBreakerType", "mainBreakerModel", "mainBreakerAmpere", "mainBreakerReference", "mainBreakerEvidence", "cabinetCount",
        "jobNumber", "revision", "supplyVoltage", "frequency", "earthingSystem",
        "ipRating", "formSeparation", "enclosureSize", "standards", "notes",
      ],
      properties: {
        number: { type: "string", description: "Exact board/drawing number from the relevant title block." },
        name: { type: "string", description: "Board name or description, separate from the project name." },
        customer: { type: "string", description: "Customer or client explicitly named on the drawing." },
        project: { type: "string", description: "Project, site or building name, separate from customer." },
        type: { type: "string", description: "Best supported board classification. Prefer the printed type; otherwise infer from the board purpose, topology and installed equipment." },
        typeConfidence: { type: "string", description: "Confidence in the board type guess: high, medium or low." },
        typeEvidence: { type: "string", description: "Short visible or schematic evidence used to classify the board type." },
        manufacturer: { type: "string", description: "Board/enclosure manufacturer exactly as printed, including Tamhash, Yakir or Rittal; empty only when unstated." },
        manufacturerRole: { type: "string", description: "Role of the chosen manufacturer name: enclosure_manufacturer, panel_builder, electrical_contractor, customer, designer or unknown." },
        manufacturerEvidence: { type: "string", description: "Short visible label/logo evidence supporting the enclosure manufacturer choice." },
        manufacturerCandidates: {
          type: "array", maxItems: 12,
          items: {
            type: "object", required: ["name", "role", "evidence", "sourcePage"],
            properties: {
              name: { type: "string" }, role: { type: "string" }, evidence: { type: "string" },
              sourcePage: { type: "integer", minimum: 0 },
            },
          },
        },
        mainBreakerType: { type: "string", description: "Main incomer type, such as MCCB, ACB, MCB, changeover switch or isolator." },
        mainBreakerModel: { type: "string", description: "Exact manufacturer/model printed for the main incomer." },
        mainBreakerAmpere: { type: "string", description: "Main incomer current rating including unit." },
        mainBreakerReference: { type: "string", description: "Exact tag/reference of the one board-level incoming device." },
        mainBreakerEvidence: { type: "string", description: "Concise source-to-device-to-common-bus path proving why this is the board main rather than a sectional field main." },
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
    pageBoards: {
      type: "array", maxItems: 500,
      items: {
        type: "object", required: ["page", "boardNumber"],
        properties: {
          page: { type: "integer", minimum: 1 },
          boardNumber: { type: "string", description: "Board number governing this PDF page; empty only when it cannot be associated safely." },
        },
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
          "curve", "sensitivity", "quantity", "reference", "sourcePage", "boardNumber", "supplyRole",
          "isMainBreaker",
        ],
        properties: {
          rawText: { type: "string", description: "Representative schematic callout or device label transcribed from the source." },
          manufacturer: { type: "string", description: "Manufacturer exactly as printed; empty when absent." },
          model: { type: "string", description: "Manufacturer model/series exactly as printed, preserving significant suffixes. Never a circuit tag, a current or a pole notation; empty when no model is printed." },
          type: { type: "string", description: "Printed device type such as MCB, MCCB, contactor or meter." },
          rating: { type: "string", description: "Device current including A, separated from curve and poles; for example C16 or 6A + N must return 16A or 6A." },
          poles: { type: "string", description: "Pole count normalized from the device callout, for example 6A + N means 1P+N." },
          curve: { type: "string", description: "Trip curve/class exactly as printed; for example C16 means curve C." },
          sensitivity: { type: "string", description: "RCD sensitivity exactly as printed." },
          quantity: { type: "integer", minimum: 0, maximum: 999, description: "Count of unique physical schematic device references; 0 when it cannot be determined safely." },
          reference: { type: "string", description: "Exact unique device tag(s) included in the quantity." },
          sourcePage: { type: "integer", minimum: 0, description: "First one-based schematic page using this device group; 0 when unknown." },
          boardNumber: { type: "string", description: "Exact board number whose schematic pages contain these counted references." },
          supplyRole: { type: "string", description: "board_main, section_main, downstream or unknown according to the single-line supply hierarchy." },
          isMainBreaker: { type: "boolean", description: "True only for the board's main incoming breaker; false for every outgoing or downstream device." },
        },
      },
    },
    doorDevices: {
      type: "array",
      maxItems: 200,
      description: "Exhaustive inventory of every physical operator or indicator position installed on the selected board's doors or control stations.",
      items: {
        type: "object",
        required: [
          "rawText", "manufacturer", "model", "type", "rating", "poles",
          "curve", "sensitivity", "quantity", "reference", "sourcePage", "boardNumber",
          "isMainBreaker",
        ],
        properties: {
          rawText: { type: "string", description: "Visible label, function, color and callout identifying this door position; required even when brand/model are unreadable." },
          manufacturer: { type: "string", description: "Manufacturer exactly as printed; empty when absent." },
          model: { type: "string", description: "Manufacturer model/series exactly as printed; never a circuit tag, a current or a pole notation; empty when unreadable or unprinted." },
          type: { type: "string", description: "Push Button, Selector Switch, Pilot Light, Emergency Stop, Door Switch, Buzzer, Main Handle or the visible operator type." },
          rating: { type: "string", description: "Operator voltage or rating exactly as printed; empty when absent." },
          poles: { type: "string", description: "Contact arrangement such as 1NO, 1NC or 1NO+1NC; empty when absent." },
          curve: { type: "string", description: "Color, maintained/spring-return action or other stock-defining visible variant." },
          sensitivity: { type: "string", description: "Empty unless explicitly applicable." },
          quantity: { type: "integer", minimum: 1, maximum: 999, description: "Number of distinct installed door positions represented by this exact specification." },
          reference: { type: "string", description: "Device tag, function label, or stable door/row/position description for every counted position." },
          sourcePage: { type: "integer", minimum: 0, description: "One-based page containing the door layout or operator schedule." },
          boardNumber: { type: "string", description: "Exact selected board number." },
          isMainBreaker: { type: "boolean", description: "True only when this row is the board's main incoming device rather than its door handle accessory." },
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
  const targetNumber = targetBoardNumberFromFileName(named);
  const responseShape = {
    board: {
      number: "", name: "", customer: "", project: "", type: "", typeConfidence: "", typeEvidence: "", manufacturer: "",
      manufacturerRole: "", manufacturerEvidence: "", manufacturerCandidates: [{ name: "", role: "", evidence: "", sourcePage: 0 }],
      mainBreakerType: "", mainBreakerModel: "", mainBreakerAmpere: "", mainBreakerReference: "", mainBreakerEvidence: "", cabinetCount: 0,
      cabinetWidths: "", buildFormat: "",
      jobNumber: "", revision: "", supplyVoltage: "", frequency: "", earthingSystem: "",
      ipRating: "", formSeparation: "", enclosureSize: "", standards: [], notes: "",
    },
    pageBoards: [{ page: 1, boardNumber: "" }],
    components: [{
      rawText: "", manufacturer: "", model: "", type: "", rating: "", poles: "",
      curve: "", sensitivity: "", quantity: 0, reference: "", sourcePage: 0, boardNumber: "", supplyRole: "unknown", isMainBreaker: false,
    }],
    doorDevices: [{
      rawText: "", manufacturer: "", model: "", type: "", rating: "", poles: "",
      curve: "", sensitivity: "", quantity: 1, reference: "", sourcePage: 0, boardNumber: "", isMainBreaker: false,
    }],
    warnings: [],
  };
  return [
    "Read the complete electrical board document and extract the relevant title block,",
    "main incomer and every component actually used across the schematic and installed-equipment layout pages. Trace the external source path to the common board bus, distinguish the one board_main device from UPS/live/essential section_main devices, and include every one of them in components with the correct supplyRole.",
    "Count quantity from unique physical device references or labelled installed positions in board-specific door/control-station layouts, not from the final-page parts list.",
    "A pilot or indicator lamp's lens colour is stock-defining: red and green are different parts, so return the visible colour in curve whenever one is shown, and never infer one that is not.",
    "Fill doorDevices using a dedicated exhaustive door-layout pass. Sweep every target-board door and control station left-to-right and top-to-bottom; return every switch, button and lamp position, including positions whose manufacturer or model is unreadable. Never stop after the first recognized operator. A labelled door elevation is valid installation evidence.",
    "Use components for the remaining installed devices. If a door device also appears in the schematic, keep its physical tag in doorDevices so the server can merge it instead of counting it twice.",
    "Before returning JSON, perform one final document-wide aggregation: identical manufacturer + model + rating + poles + curve + sensitivity must be one component row with the total unique-device quantity across every target-board page. sourcePage is traceability only and must never create a separate row.",
    "Classify the board into the closest supported PanelVault type. Prefer an explicit title-block type; if none is printed, make a reviewable best guess from the board name, incoming/outgoing topology, loads and installed equipment, and return confidence plus concise evidence.",
    "First map every PDF page to its governing title-block board number in pageBoards. Count components only after that map is complete, and put that board number on every component line.",
    "For every breaker, separate its current, poles and trip curve: C16 is rating 16A with curve C; 6A + N is rating 6A with poles 1P+N. Never confuse 6kA breaking capacity with a 6A current rating.",
    targetNumber ? `MANDATORY TARGET BOARD: "${targetNumber}" was inferred from the upload filename "${named.slice(0, 200)}". Extract only pages mapped to this exact board number. If it is not visibly present, return no components and explain that in warnings; never substitute the preceding, following, nearest, or primary board.` : named ? `The upload filename is "${named.slice(0, 200)}". Use it only to select the matching board or confirm an exact board number; do not derive other fields from it.` : "",
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
  // Read the bulletin before spaces are squeezed out, or "800F pilot light"
  // reads as the plastic 800FP. 800FM is the metal 800F by its catalog number.
  const allenBradleyBulletin = String(value).toLowerCase().match(/^\s*(800f|800t|802t)([pm])?(?![a-z])/);
  if (allenBradleyBulletin) {
    keys.add(allenBradleyBulletin[1] + (allenBradleyBulletin[2] === "p" ? "p" : ""));
  }
  let withoutRangeWords = raw;
  for (const prefix of ["acti9", "sace", "tmax", "sentron"]) {
    if (withoutRangeWords.startsWith(prefix)) withoutRangeWords = withoutRangeWords.slice(prefix.length);
  }
  if (withoutRangeWords) keys.add(withoutRangeWords);
  if (/^s20[1-4]m$/.test(withoutRangeWords)) keys.add(withoutRangeWords.slice(0, -1));
  const tmaxVariant = withoutRangeWords.match(/^(xt[1-7])[cdn]$/);
  if (tmaxVariant) keys.add(tmaxVariant[1]);
  // F202A / F204A print the residual-current type as a suffix; the pole count
  // in front of it is what names the catalog family.
  if (/^f20[1-4]a$/.test(withoutRangeWords)) keys.add(withoutRangeWords.slice(0, -1));
  // SATEC prints "PM130E" as often as "PM130E PLUS"; the letters before PLUS
  // are the variant, so they alone must still find it rather than tie with EH.
  const satecPlus = withoutRangeWords.match(/^(pm130(?:p|e|eh))plus$/);
  if (satecPlus) keys.add(satecPlus[1]);
  // ABB manual motor starters often print the adjustable-range suffix or an
  // order code beside the family: "MS116-16 / 1SAM...". The catalog stores
  // the MS116 family, which is the stable identity across those variants.
  const abbMotorStarter = String(value).toLowerCase().match(/(?:^|[^a-z0-9])ms\s*[- ]?(116|132)(?=$|[^a-z0-9])/);
  if (abbMotorStarter) keys.add(`ms${abbMotorStarter[1]}`);
  for (const token of String(value).toLowerCase().split(/[^a-z0-9]+/)) {
    const family = [...HAGER_FAMILIES, ...FRAME_FAMILIES].find(([pattern]) => pattern.test(token));
    if (family) keys.add(family[1]);
  }
  return [...keys].filter((key) => key.length >= 3);
}

/** A drawing prints Hager's full order reference (EPN524, EPS450B, EEN101),
 * while the catalog row is the family, so each reference reads as a family key
 * that only that row also carries. The key is prefixed so that no substring
 * match can reach another brand's model ("een" is inside "green").
 *
 * The EPN050-053 add-ons and the EEN002/003 spare cells are accessories and
 * deliberately left out: a spare cell on a drawing is not a second switch.
 * The EZ timers and the EMN001 need no entry, because their reference is
 * already the catalog model. */
const HAGER_FAMILIES = [
  [/^epn5\d\d$/, "hagerepn"],
  [/^epn$/, "hagerepn"],
  [/^eps4[15]0b?$/, "hagereps"],
  [/^(?:60060|ed183)$/, "hagerloadshed"],
  [/^een10[01]$/, "hagereen"],
];

/** Some catalog rows are a frame range rather than one device — ABB's
 * "AX range (AX09-AX260)" stands for every AX frame. A drawing prints the
 * frame it uses, AX95 or AX185, which resembles nothing in that row's name, so
 * the row could only ever be reached by guessing from brand and poles. Both
 * sides now read as one family key, and the row is found by what is printed. */
const FRAME_FAMILIES = [
  [/^ax\d{2,3}$/, "abbax"],
];

/** Canonical current carried by a breaker callout. This deliberately requires
 * the A to follow the number directly, so 6kA breaking capacity is never
 * mistaken for a 6A trip rating. MCB shorthand such as C16 is accepted. */
function ampereRating(...values) {
  // Drawings print poles and current together: "3X40A", "2x40A", "3×63A".
  for (const value of values) {
    const poled = String(value || "").toUpperCase().match(/(?:^|[^A-Z0-9])\d\s*[X×]\s*(\d+(?:\.\d+)?)\s*A(?![A-Z])/);
    if (poled) return `${Number(poled[1])}A`;
  }
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
  if (["mpcb", "manualmotorstarter", "motorprotectioncircuitbreaker", "motorprotectivecircuitbreaker"].includes(key)) return "mpcb";
  if (["button", "pushbutton", "pushbuttonoperator", "pushbuttonswitch", "momentarypushbutton"].includes(key)) return "pushbutton";
  if (["lamp", "pilot", "pilotlight", "pilotlightoperator", "pilotlamp", "indicator", "indicatorlight", "indicatorlamp", "signallamp", "controllamp"].includes(key)) return "pilotlight";
  if (["selectorswitch", "selector", "keyswitch", "keyselectorswitch"].includes(key)) return "selectorswitch";
  if (["emergencystop", "emergencystopbutton", "emergencystopoperator", "estop", "estopbutton"].includes(key)) return "emergencystop";
  if (["doorswitch", "doorpositionswitch", "limitswitch", "doorlimitswitch"].includes(key)) return "doorswitch";
  if (["latchingrelay", "impulserelay", "teleruptor", "impulseswitch", "remoteswitch", "bistablerelay", "steprelay"].includes(key)) return "latchingrelay";
  if (["timer", "timerelay", "timedelayrelay", "timingrelay", "staircasetimer", "staircaseswitch", "staircasetimelagswitch", "timelagswitch"].includes(key)) return "timer";
  if (["twilightswitch", "photocell", "photocellswitch", "lightsensitiveswitch", "dusksensor", "daylightswitch"].includes(key)) return "twilightswitch";
  if (["loadsheddingrelay", "loadshedder", "loadshedding", "intensityrelay"].includes(key)) return "loadsheddingrelay";
  return key;
}

function manufacturerKey(value) {
  const key = partKey(value);
  if (["ab", "allenbradley", "rockwell", "rockwellautomation"].includes(key)) return "allenbradley";
  if (["moeller", "eatonmoeller", "kloecknermoeller", "klocknermoeller"].includes(key)) return "eaton";
  return key;
}

/** Lens colour of a lamp. Catalog rows carry it at the end of the model
 * ("M22 pilot light, red"); a drawing puts it in the variant, the label or the
 * callout, in English or Hebrew. Only the colours the catalog splits on. */
const LENS_COLOURS = { red: ["red", "אדום", "אדומה"], green: ["green", "ירוק", "ירוקה"] };

function lensColour(...values) {
  const found = new Set();
  for (const value of values) {
    const source = String(value || "").toLowerCase();
    for (const [colour, words] of Object.entries(LENS_COLOURS)) {
      if (words.some((word) => new RegExp(`(^|[^\\p{L}])${word}($|[^\\p{L}])`, "u").test(source))) found.add(colour);
    }
  }
  // A line naming both colours is a group, not one lamp.
  return found.size === 1 ? [...found][0] : "";
}

/** The single current a catalog row states outright, as opposed to a range.
 *
 * A contactor row states its duty after the current — "190A AC-3, 90kW" — and
 * requiring the whole string to be the current meant no such row ever counted
 * as exact. A range row like the AX frames' "9-260A" then scored for covering
 * the current while AF190 scored nothing for being it, so every ABB contactor
 * on a drawing landed on the range row whatever its size. The current has to
 * lead the string: "IEC 160A frame" is a frame size, not a rating. */
function exactAmpereRating(value) {
  const source = String(value || "").trim();
  if (ampereRange(source)) return "";
  const leading = source.match(/^(\d+(?:\.\d+)?)\s*A\b/i);
  return leading ? ampereRating(`${leading[1]}A`) : "";
}

function ampereRange(value) {
  const source = String(value || "").toUpperCase();
  const match = source.match(/(?:^|[^\d.])(\d+(?:\.\d+)?)\s*[-–—]\s*(\d+(?:\.\d+)?)\s*A(?:$|[^A-Z])/);
  if (!match) return null;
  const minimum = Number(match[1]);
  const maximum = Number(match[2]);
  return Number.isFinite(minimum) && Number.isFinite(maximum) && minimum <= maximum
    ? { minimum, maximum } : null;
}

/** Model keys for a printed line rather than for a model on its own.
 *
 * `modelKeys` squeezes everything it is given into a single key, which is what
 * a model field needs ("SACE Tmax XT1" -> "sacetmaxxt1") and useless for a
 * callout: "QC200 ABB AF38 38A" would become one key that matches nothing. So
 * the line is read token by token, and each token is also split on the
 * separators inside an order code, because AF38-30-00 is an AF38. */
function modelKeysFromText(value) {
  const tokens = String(value || "").split(/[^A-Za-z0-9.\-/]+/).filter(Boolean);
  const keys = new Set();
  for (let index = 0; index < tokens.length; index += 1) {
    for (const piece of [tokens[index], ...tokens[index].split(/[-/]/)]) {
      for (const key of modelKeys(piece)) keys.add(key);
    }
    // A catalog model of several words squeezes into a single key — "OT switch
    // disconnector" becomes "otswitchdisconnector" — so neighbouring words on
    // the line are joined the same way before they are compared.
    let joined = tokens[index];
    for (let span = 1; span < 4 && index + span < tokens.length; span += 1) {
      joined += ` ${tokens[index + span]}`;
      for (const key of modelKeys(joined)) keys.add(key);
    }
  }
  return [...keys];
}

function sameModel(left, right) {
  const leftKeys = modelKeys(left);
  const rightKeys = modelKeys(right);
  return leftKeys.some((key) => rightKeys.includes(key));
}

/** Lamps are bought as one house brand, so an unbranded lamp on a drawing is
 * not really unknown — it is whatever the shop fits. The assumption lives here
 * rather than in the prompt: the reading stays an honest record of what is
 * printed, and what PanelVault does with a blank brand stays deterministic,
 * visible in one place and testable.
 *
 * It applies only when the drawing names neither brand nor model. A printed
 * model that fails to match is a genuine question for a person, never this.
 * Colour is still required, because it decides which lamp is ordered. */
const HOUSE_DEFAULTS = [
  { type: "pilotlight", family: "salzer-sz22", byColour: true },
];

function houseDefaultPart(catalog, part) {
  if (manufacturerKey(part.manufacturer)) return null;
  if (modelKeys(part.model).length) return null;
  const requestedType = typeKey(part.type);
  const preference = HOUSE_DEFAULTS.find((entry) => entry.type === requestedType);
  if (!preference) return null;

  let id = preference.family;
  if (preference.byColour) {
    const colour = lensColour(part.curve, part.rawText, part.reference);
    if (!colour) return null;
    id = `${preference.family}-${colour}`;
  }
  return catalog.find((candidate) => candidate.id === id) || null;
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
  // A precise order code may occupy `model` while the family name appears in
  // the representative callout. Preserve the conservative default, but carry
  // recognized ABB motor-protection family keys over from rawText.
  if (part.model && part.rawText) {
    for (const key of modelKeys(part.rawText)) {
      if (/^ms(?:116|132)$/.test(key) && !models.includes(key)) models.push(key);
    }
  }
  const manufacturer = manufacturerKey(part.manufacturer);
  const requestedType = typeKey(part.type);
  const requestedPoles = poleKey(part.poles, part.rawText, part.rating);
  const requestedAmpere = ampereRating(part.rating, part.rawText);
  const requestedColour = lensColour(part.curve, part.model, part.rawText);

  const scoreCatalog = (wanted, exactOnly) => catalog
    .map((candidate) => {
      const candidateModels = modelKeys(candidate.model);
      if (!candidateModels.length) return null;

      let score = 0;
      for (const model of wanted) {
        for (const candidateModel of candidateModels) {
          if (candidateModel === model) score = Math.max(score, 3);
          // A key read out of a whole printed line has to be the model, not a
          // fragment of one: loose matching there would let "abb" or a rating
          // reach a family nobody printed.
          else if (!exactOnly && (candidateModel.includes(model) || model.includes(candidateModel))) score = Math.max(score, 2);
        }
      }
      const modelMatched = score > 0;
      // A model alone is ambiguous across brands — several ranges share
      // numbers — so the brand must agree whenever the drawing names one.
      if (manufacturer) {
        const candidateManufacturer = manufacturerKey(candidate.manufacturer);
        if (candidateManufacturer !== manufacturer
          && !candidateManufacturer.includes(manufacturer)
          && !manufacturer.includes(candidateManufacturer)) return null;
        score += 1;
      }

      const candidateType = typeKey(candidate.type);
      const candidatePoles = poleKey(candidate.poles);
      const candidateAmpere = exactAmpereRating(candidate.rating);
      const candidateAmpereRange = ampereRange(candidate.rating);

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
        const fixedABBMotorStarter = manufacturerKey(candidate.manufacturer) === "abb"
          && candidateModels.some((key) => /^ms(?:116|132)$/.test(key))
          && models.some((key) => candidateModels.includes(key));
        // MS116/MS132 are intrinsically three-pole families. A one-line symbol
        // is sometimes read as 1P even when the printed family is unambiguous;
        // keep the exact family match and let its catalog row supply 3P.
        if (requestedPoles !== candidatePoles && !fixedABBMotorStarter) return null;
        score += 2;
      }
      if (requestedAmpere && candidateAmpere) {
        if (requestedAmpere !== candidateAmpere) return null;
        score += 3;
      } else if (requestedAmpere && candidateAmpereRange) {
        const requested = Number(requestedAmpere.replace(/A$/i, ""));
        if (requested < candidateAmpereRange.minimum || requested > candidateAmpereRange.maximum) return null;
        score += 1;
      }
      // A lamp of the other colour is ruled out, but the right colour earns
      // nothing: a colour must not lift a weaker model match into a tie.
      const candidateColour = lensColour(candidate.model);
      if (requestedColour && candidateColour && requestedColour !== candidateColour) return null;
      return { candidate, score, modelMatched };
    })
    .filter(Boolean)
    .sort((a, b) => b.score - a.score);

  // `ambiguous` distinguishes "two parts answered and neither wins" from
  // "nothing answered". A tie is a question for a person, so a later, weaker
  // pass must not go on to answer it.
  const resolve = (wanted, exactOnly = false) => {
    const all = scoreCatalog(wanted, exactOnly);
    /* A model that is actually printed outranks one inferred from brand, type
       and poles, however well the inference scores. Without this an ABB
       contactor drawn as AX185 could be answered with AF190, because being
       exactly 190A scored higher than being the AX range it names. */
    const named = all.filter((entry) => entry.modelMatched);
    const scored = named.length ? named : all;
    if (!scored.length) return { part: null, ambiguous: false };
    if (scored.length > 1
      && scored[0].score === scored[1].score
      && scored[0].candidate.id !== scored[1].candidate.id) {
      return { part: null, ambiguous: true };
    }
    return { part: scored[0].candidate, ambiguous: false };
  };

  /* Evidence is taken in the order of how much it proves, because the model
     field of a schematic line is not always a model: first that field naming a
     catalog model outright, then a model printed elsewhere on the line, and
     only then a partial resemblance to the model field. That last step is where
     a tag does real damage — "F12" sits inside "AF12", so a tag could quietly
     select a contactor nobody drew — so a model actually printed on the line
     now outranks it. */
  const exact = resolve(models, true);
  if (exact.part) return exact.part;
  // A tie here is not decisive the way a tie on a printed model is: when the
  // model field holds a tag, nothing in this pass matched a model at all, and
  // the candidates only tied on brand, type and poles. The line still deserves
  // its turn.

  /* Nothing answered to the model field. On a schematic that field often holds
     the circuit tag — QC200, KM3, -Q1 — because the tag is what is printed at
     the symbol, while the device itself is named beside it or in the schedule.
     So read the models out of the whole printed line and try those.

     Only exact keys count here, and every other gate still applies: the brand
     the drawing names must agree, as must type, poles and current, and a tie is
     still refused. A line that prints no model at all stays unmatched. */
  const printed = modelKeysFromText(`${part.model || ""} ${part.rawText || ""}`)
    .filter((key) => !models.includes(key));
  if (printed.length) {
    const fromLine = resolve(printed, true);
    if (fromLine.part) return fromLine.part;
    if (fromLine.ambiguous) return null;
  }

  const resembling = resolve(models);
  if (resembling.part) return resembling.part;

  return houseDefaultPart(catalog, part);
}

const text = (value, max) => String(value ?? "").trim().slice(0, max);

function firstSourcePage(left, right) {
  const pages = [left, right].map((value) => Math.trunc(Number(value) || 0)).filter((value) => value > 0);
  return pages.length ? Math.min(...pages) : 0;
}

function referenceTokens(value) {
  const source = String(value || "").toUpperCase();
  const tokens = new Set();
  const rangePattern = /([A-Z]{1,8})\s*[-_]?\s*(\d+)\s*[-–—]\s*(?:([A-Z]{1,8})\s*[-_]?\s*)?(\d+)/g;
  let match;
  while ((match = rangePattern.exec(source))) {
    const startPrefix = match[1];
    const endPrefix = match[3] || startPrefix;
    const start = Number(match[2]);
    const end = Number(match[4]);
    if (startPrefix !== endPrefix || end < start || end - start > 999) continue;
    for (let number = start; number <= end; number += 1) tokens.add(`${startPrefix}${number}`);
  }
  const singlePattern = /(?:^|[^A-Z0-9])([A-Z]{1,8})\s*[-_]?\s*(\d+)(?=$|[^A-Z0-9])/g;
  while ((match = singlePattern.exec(source))) tokens.add(`${match[1]}${Number(match[2])}`);
  return tokens;
}

function componentIdentity(line) {
  if (line.partID) return `part:${partKey(line.partID)}`;
  const models = modelKeys(line.model);
  const model = models.sort((left, right) => left.length - right.length)[0] || "";
  if (model) return `model:${model}|type:${typeKey(line.type)}`;
  const structured = [line.manufacturer, line.type].map(partKey).filter(Boolean);
  if (structured.length) return `structured:${structured.join("|")}|${partKey(line.description || line.rawText)}`;
  return `raw:${partKey(line.description || line.rawText)}`;
}

function componentAxis(line, field) {
  if (field === "rating") return partKey(ampereRating(line.rating) || line.rating);
  if (field === "poles") return partKey(poleKey(line.poles) || line.poles);
  return partKey(line[field]);
}

function compatibleComponentSpecifications(left, right) {
  if (componentIdentity(left) !== componentIdentity(right)) return false;
  return ["manufacturer", "rating", "poles", "curve", "sensitivity"].every((field) => {
    const leftValue = componentAxis(left, field);
    const rightValue = componentAxis(right, field);
    return !leftValue || !rightValue || leftValue === rightValue;
  });
}

/** One exact specification appears once in the board, regardless of page.
 * Missing OCR axes are allowed to join a matching populated specification,
 * while conflicting ratings/poles/curves remain separate. Repeated reference
 * ranges are counted once; distinct ranges contribute to the document total. */
function consolidateComponents(lines) {
  const consolidated = [];
  for (const line of Array.isArray(lines) ? lines : []) {
    let group = consolidated.find((candidate) => compatibleComponentSpecifications(candidate.line, line));
    if (!group) {
      group = { line: { ...line }, referenceGroups: new Map(), unreferencedQuantity: 0 };
      consolidated.push(group);
    }

    const existing = group.line;
    for (const field of ["manufacturer", "model", "type", "rating", "poles", "curve", "sensitivity", "rawText", "description"]) {
      if (!existing[field] && line[field]) existing[field] = line[field];
    }
    if (!existing.partID && line.partID) existing.partID = line.partID;

    const incomingReference = text(line.reference, 120);
    const incomingQuantity = Math.max(1, Math.trunc(Number(line.quantity) || 1));
    if (incomingReference) {
      const key = partKey(incomingReference);
      const previous = group.referenceGroups.get(key);
      if (!previous || incomingQuantity > previous.quantity) {
        group.referenceGroups.set(key, {
          reference: incomingReference,
          quantity: incomingQuantity,
          tokens: referenceTokens(incomingReference),
        });
      }
    } else {
      group.unreferencedQuantity += incomingQuantity;
    }
    existing.sourcePage = firstSourcePage(existing.sourcePage, line.sourcePage);
  }

  return consolidated.map(({ line, referenceGroups, unreferencedQuantity }) => {
    const groups = [...referenceGroups.values()];
    const allReferencesReliable = groups.length > 0
      && groups.every((group) => group.tokens.size === group.quantity);
    const uniqueTokens = new Set(groups.flatMap((group) => [...group.tokens]));
    const referencedQuantity = allReferencesReliable
      ? uniqueTokens.size
      : groups.reduce((sum, group) => sum + group.quantity, 0);
    return {
      ...line,
      quantity: Math.min(9999, referencedQuantity + unreferencedQuantity),
      reference: groups.map((group) => group.reference).join(", ").slice(0, 120),
    };
  });
}

function supplyRoleKey(value) {
  return String(value || "").toLowerCase().replace(/[^a-z]+/g, "_").replace(/^_+|_+$/g, "");
}

function findMainBreakerPart(parts, board) {
  const mainModel = text(board?.mainBreakerModel, 80);
  const mainReference = partKey(board?.mainBreakerReference);
  const candidates = Array.isArray(parts) ? parts : [];
  const ranked = candidates
    .map((part, index) => {
      const wording = `${part?.reference || ""} ${part?.rawText || ""}`;
      const role = supplyRoleKey(part?.supplyRole);
      const modelMatches = mainModel && sameModel(part?.model || part?.rawText, mainModel);
      let rank = 0;
      if (role === "board_main") rank += 300;
      if (role === "section_main") rank -= 300;
      if (part?.isMainBreaker === true) rank += 150;
      if (mainReference && referenceTokens(part?.reference).has(mainReference.toUpperCase())) rank += 140;
      else if (mainReference && partKey(part?.reference) === mainReference) rank += 140;
      if (/main\s*(?:incomer|incoming|breaker)|incomer|incoming/i.test(wording)) rank += 50;
      if (/common\s*(?:bus|busbar)|utility|transformer|generator|source\s*(?:1|2|i|ii)|normal\s*(?:and|\/|\+)\s*(?:emergency|generator)/i.test(wording)) rank += 60;
      if (/(?:ups|live|essential|emergency)\s*(?:field|section)|sectional|sub[- ]?main|field\s*(?:main|incomer)/i.test(wording)) rank -= 90;
      if (modelMatches) rank += 20;
      if (Math.max(1, Math.trunc(Number(part?.quantity) || 1)) === 1) rank += 5;
      const ampere = ampereRating(part?.rating, part?.rawText);
      if (ampere) rank += 10;
      return { part, index, rank, ampere, role };
    })
    .filter((candidate) => candidate.rank >= 35 && candidate.role !== "section_main")
    .sort((left, right) => right.rank - left.rank || left.index - right.index);
  return ranked[0] || null;
}

function storedMainBreakerModel(part, fallback) {
  const model = text(part?.model || fallback, 80);
  const manufacturer = text(part?.manufacturer, 60);
  if (!manufacturer || !model || partKey(model).startsWith(partKey(manufacturer))) return model;
  return text(`${manufacturer} ${model}`, 120);
}

function canonicalMainBreakerType(part, fallback) {
  const source = `${part?.type || ""} ${part?.model || ""}`;
  if (/changeover|transfer\s*switch|\bATS\b|\bATyS\b|SIRCO|SIRCOVER|COMO\s+CS/i.test(source)) return "Changeover Switch";
  return text(part?.type || fallback, 40);
}

/** Turn a raw model reading into the payload the phone consumes.
 *
 * Every field is clamped here rather than trusted: this is model output, and
 * it reaches a board draft that a workshop builds from.
 */
function normalizeReading(reading, catalog, options = {}) {
  const board = reading?.board || {};
  const fileTarget = targetBoardNumberFromFileName(options.fileName);
  const readBoardNumber = text(board.number, 60);
  const selectedBoardNumber = fileTarget || readBoardNumber;
  const readMatchesTarget = !fileTarget || !readBoardNumber
    || boardNumberKey(fileTarget) === boardNumberKey(readBoardNumber);
  const warnings = (Array.isArray(reading?.warnings) ? reading.warnings : [])
    .map((warning) => text(warning, 240))
    .filter(Boolean);
  if (!readMatchesTarget) {
    warnings.unshift(`Ignored board ${readBoardNumber}: upload target ${fileTarget} is required.`);
  }

  const pageBoardNumbers = new Map((Array.isArray(reading?.pageBoards) ? reading.pageBoards : [])
    .map((entry) => [Math.trunc(Number(entry?.page) || 0), text(entry?.boardNumber, 60)])
    .filter(([page, number]) => page > 0 && number));
  const extractedParts = [
    // Door devices get first claim on the safety cap. They are the easiest
    // items for a long power schedule to crowd out, and the dedicated ledger
    // exists specifically so every physical operator survives normalization.
    ...(Array.isArray(reading?.doorDevices) ? reading.doorDevices.slice(0, 200) : []),
    ...(Array.isArray(reading?.components) ? reading.components.slice(0, 200) : []),
  ];
  const parts = extractedParts.filter((part) => {
    if (!selectedBoardNumber) return true;
    const claimedBoard = text(part?.boardNumber, 60);
    const sourcePage = Math.trunc(Number(part?.sourcePage) || 0);
    const pageBoard = pageBoardNumbers.get(sourcePage) || "";
    const belongs = claimedBoard || pageBoard;
    if (belongs && boardNumberKey(belongs) !== boardNumberKey(selectedBoardNumber)) {
      warnings.push(`Skipped component ${text(part?.reference || part?.rawText || part?.model, 80) || "line"} from board ${belongs}.`);
      return false;
    }
    // When Gemini selected another board entirely, unlabelled component lines
    // cannot be trusted. New prompts always provide boardNumber/pageBoards.
    if (!readMatchesTarget && !belongs) {
      warnings.push(`Skipped an unlabelled component because board ${fileTarget} was not selected.`);
      return false;
    }
    return true;
  });
  const declaredMainModel = text(board.mainBreakerModel, 80);
  const boardMainAmpere = ampereRating(board.mainBreakerAmpere);
  const mainBreakerPart = findMainBreakerPart(parts, board);
  const mainModel = storedMainBreakerModel(mainBreakerPart?.part, declaredMainModel);
  const mainType = canonicalMainBreakerType(mainBreakerPart?.part, board.mainBreakerType);
  const mainAmpere = mainBreakerPart?.ampere || boardMainAmpere;
  if (mainBreakerPart?.part && declaredMainModel && !sameModel(mainBreakerPart.part.model || mainBreakerPart.part.rawText, declaredMainModel)) {
    warnings.push(`Main incoming device was corrected from ${declaredMainModel} to ${mainModel} using the source-to-common-bus hierarchy.`);
  }
  if (mainBreakerPart?.ampere && boardMainAmpere && mainBreakerPart.ampere !== boardMainAmpere) {
    warnings.push(`Main breaker current was corrected from ${boardMainAmpere} to ${mainBreakerPart.ampere} using its installed-device callout.`);
  }
  if (readMatchesTarget && declaredMainModel && !mainBreakerPart) {
    parts.unshift({
      rawText: [board.mainBreakerType, declaredMainModel, mainAmpere].filter(Boolean).join(" "),
      manufacturer: "",
      model: declaredMainModel,
      type: text(board.mainBreakerType, 60),
      rating: mainAmpere,
      poles: "",
      curve: "",
      sensitivity: "",
      quantity: 1,
      reference: "Main incomer",
      sourcePage: 0,
      boardNumber: selectedBoardNumber,
      isMainBreaker: true,
    });
  }

  const components = [];
  const unmatched = [];
  // The response contract permits 200 door rows and 200 schematic rows. Do
  // not re-apply a 200-row cap after combining them: that used to discard the
  // tail of otherwise valid scans, usually the ordinary schematic components
  // because door positions intentionally receive first claim above.
  for (const part of parts) {
    const quantity = Math.min(Math.max(Math.trunc(Number(part.quantity) || 1), 1), 999);
    const isMain = part === mainBreakerPart?.part || supplyRoleKey(part?.supplyRole) === "board_main"
      || (part?.isMainBreaker === true && supplyRoleKey(part?.supplyRole) !== "section_main")
      || (mainModel && sameModel(part?.model || part?.rawText, mainModel)
        && /main|incomer|incoming/i.test(String(part?.reference || "")));
    const detectedAmpere = isMain ? mainAmpere || ampereRating(part.rating, part.rawText)
      : ampereRating(part.rating, part.rawText);
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

  const safeBoard = readMatchesTarget ? board : {};
  return {
    board: {
      number: selectedBoardNumber,
      name: text(safeBoard.name, 120),
      customer: text(safeBoard.customer, 120),
      project: text(safeBoard.project, 120),
      type: text(safeBoard.type, 60),
      typeConfidence: /^(?:high|medium|low)$/i.test(String(safeBoard.typeConfidence || "").trim())
        ? String(safeBoard.typeConfidence).trim().toLowerCase() : "low",
      typeEvidence: text(safeBoard.typeEvidence, 240),
      manufacturer: resolveBoardManufacturer(safeBoard),
      mainBreakerType: readMatchesTarget ? mainType : "",
      mainBreakerModel: readMatchesTarget ? mainModel : "",
      mainBreakerAmpere: readMatchesTarget ? mainAmpere || text(safeBoard.mainBreakerAmpere, 20) : "",
      mainBreakerReference: readMatchesTarget ? text(mainBreakerPart?.part?.reference || safeBoard.mainBreakerReference, 120) : "",
      mainBreakerEvidence: readMatchesTarget ? text(safeBoard.mainBreakerEvidence, 300) : "",
      cabinetCount: Math.min(Math.max(Math.trunc(Number(safeBoard.cabinetCount) || 1), 1), 40),
      cabinetWidths: text(safeBoard.cabinetWidths, 80),
      buildFormat: ["Panels", "Plate"].includes(String(safeBoard.buildFormat || "").trim())
        ? String(safeBoard.buildFormat).trim() : "",
      jobNumber: text(safeBoard.jobNumber, 60),
      revision: text(safeBoard.revision, 60),
      supplyVoltage: text(safeBoard.supplyVoltage, 40),
      frequency: text(safeBoard.frequency, 30),
      earthingSystem: text(safeBoard.earthingSystem, 30),
      ipRating: text(safeBoard.ipRating, 30),
      formSeparation: text(safeBoard.formSeparation, 40),
      enclosureSize: text(safeBoard.enclosureSize, 80),
      standards: (Array.isArray(safeBoard.standards) ? safeBoard.standards : [])
        .map((standard) => text(standard, 80)).filter(Boolean).slice(0, 20),
      notes: text(safeBoard.notes, 600),
    },
    components: consolidateComponents(components),
    unmatched: consolidateComponents(unmatched),
    warnings: [...new Set(warnings)].slice(0, 20),
  };
}

module.exports = {
  BOARD_SCHEME_INSTRUCTION,
  BOARD_SCHEME_SCHEMA,
  boardSchemePrompt,
  ampereRating,
  breakerCurve,
  consolidateComponents,
  houseDefaultPart,
  matchCatalogPart,
  modelKeys,
  normalizeReading,
  partKey,
  poleKey,
  resolveBoardManufacturer,
  targetBoardNumberFromFileName,
};
