// Client for the scheme extraction service.
//
// The extractor is a separate process because the work needs poppler and
// Pillow — rendering an A1 sheet to 600 DPI and cropping the destination
// table out of it is not something this Node server should be doing. It
// speaks HTTP; this file is the only place that knows that.
//
// Nothing here parses the extraction. The service owns that contract and
// validates it against its own Pydantic models; re-validating a subset of it
// in JavaScript would only create a second, weaker opinion about the shape.

const DEFAULT_BASE_URL = "http://127.0.0.1:8100";

/** Submitting is quick — it hands back a job id. Polling is quicker still. */
const SUBMIT_TIMEOUT_MS = 60_000;
const POLL_TIMEOUT_MS = 30_000;
/** A 35-sheet set renders to a few hundred MB of PNG; the workbook is small. */
const WORKBOOK_TIMEOUT_MS = 120_000;

function serviceError(message, statusCode) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

async function readProblem(response) {
  const body = await response.json().catch(() => ({}));
  const detail = body && body.detail;
  if (typeof detail === "string" && detail.trim()) return detail.trim();
  // FastAPI reports validation failures as an array of per-field objects.
  if (Array.isArray(detail) && detail.length) {
    return detail.map((item) => item && item.msg).filter(Boolean).join("; ")
      || "The extraction service rejected that request.";
  }
  return `The extraction service returned ${response.status}.`;
}

function createSchemeExtractorClient({
  baseUrl = process.env.SCHEME_EXTRACTOR_URL || DEFAULT_BASE_URL,
  fetchImpl = globalThis.fetch,
} = {}) {
  if (typeof fetchImpl !== "function") throw new Error("The scheme extractor requires Node.js 20 or newer.");
  // Render's dashboard labels the internal address "TCP"; accept it pasted
  // with that scheme too.
  const configuredRoot = String(baseUrl).trim().replace(/^tcp:\/\//i, "").replace(/\/+$/, "");
  // Render's `hostport` service property is intentionally scheme-less
  // (for example `panelvault-scheme-extractor:8100`). The private network is
  // HTTP, so make that Blueprint-native value directly usable by fetch.
  const root = /^https?:\/\//i.test(configuredRoot)
    ? configuredRoot
    : `http://${configuredRoot}`;

  async function call(path, { method = "GET", body, timeout } = {}) {
    let response;
    try {
      response = await fetchImpl(`${root}${path}`, {
        method,
        headers: body ? { "Content-Type": "application/json" } : undefined,
        body: body ? JSON.stringify(body) : undefined,
        signal: AbortSignal.timeout(timeout),
      });
    } catch (cause) {
      if (cause?.name === "TimeoutError" || cause?.name === "AbortError") {
        throw serviceError("The extraction service did not answer in time.", 504);
      }
      // A refused connection means the sidecar is not running. Say so plainly
      // rather than reporting it as a bad request from the phone, and name
      // where we looked and why it failed so a misconfigured deploy can be
      // told apart from a stopped one.
      const reason = cause?.cause?.code || cause?.code || cause?.message || "unknown error";
      const where = process.env.SCHEME_EXTRACTOR_URL ? new URL(root).host : "SCHEME_EXTRACTOR_URL is not set";
      console.error(`Scheme extractor unreachable at ${root}:`, cause);
      throw serviceError(`The extraction service is not reachable (${where}: ${reason}).`, 503);
    }
    if (!response.ok) throw serviceError(await readProblem(response), response.status === 404 ? 404 : 502);
    return response;
  }

  return {
    baseUrl: root,
    configured: Boolean(baseUrl),

    /** Hand the drawing over and get a job id back. */
    async submit({ fileName, data, models, useBatch }) {
      if (typeof data !== "string" || !data.trim()) {
        throw serviceError("Attach the scheme PDF.", 400);
      }
      const response = await call("/extract", {
        method: "POST",
        timeout: SUBMIT_TIMEOUT_MS,
        body: {
          fileName: fileName || "scheme.pdf",
          data: data.trim(),
          models: models || null,
          use_batch: typeof useBatch === "boolean" ? useBatch : null,
        },
      });
      return response.json();
    },

    async job(jobID) {
      if (!jobID) throw serviceError("Which job?", 400);
      const response = await call(`/jobs/${encodeURIComponent(jobID)}`, { timeout: POLL_TIMEOUT_MS });
      return response.json();
    },

    /** The reviewer's xlsx, streamed straight through. */
    async workbook(jobID) {
      if (!jobID) throw serviceError("Which job?", 400);
      const response = await call(`/jobs/${encodeURIComponent(jobID)}/workbook`, {
        timeout: WORKBOOK_TIMEOUT_MS,
      });
      return {
        body: Buffer.from(await response.arrayBuffer()),
        contentType: response.headers.get("content-type")
          || "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      };
    },

    async health() {
      const response = await call("/health", { timeout: POLL_TIMEOUT_MS });
      return response.json();
    },
  };
}

module.exports = {
  createSchemeExtractorClient,
  DEFAULT_BASE_URL,
};
