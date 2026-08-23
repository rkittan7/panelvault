const DEFAULT_MODEL = "gemini-3.6-flash";
const GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models";

// Render can retain an older environment override even after render.yaml and
// the application default move forward. Keep known retired Flash ids from
// pinning a deployment to a model that new Gemini accounts cannot call.
const MODEL_REPLACEMENTS = new Map([
  ["gemini-2.5-flash", DEFAULT_MODEL],
  ["gemini-2.5-flash-preview-05-20", DEFAULT_MODEL],
  ["gemini-2.5-flash-preview-09-25", DEFAULT_MODEL],
  ["gemini-2.0-flash", DEFAULT_MODEL],
  ["gemini-2.0-flash-001", DEFAULT_MODEL],
]);

function resolveModel(value) {
  const requested = String(value || "").trim().replace(/^models\//, "");
  return MODEL_REPLACEMENTS.get(requested) || requested || DEFAULT_MODEL;
}

function geminiErrorMessage(result) {
  const apiError = result && result.error;
  const base = apiError?.message || "Gemini request failed.";
  const violations = (Array.isArray(apiError?.details) ? apiError.details : [])
    .flatMap((detail) => detail?.fieldViolations || detail?.field_violations || [])
    .map((violation) => {
      const field = String(violation?.field || "").trim();
      const description = String(violation?.description || "").trim();
      return [field, description].filter(Boolean).join(": ");
    })
    .filter(Boolean);
  return violations.length ? `${base} ${violations.join(" ")}` : base;
}

/** Inline document parts are base64, which is 4 characters per 3 bytes. */
const MAX_DOCUMENT_BASE64 = 11_000_000; // ~8 MB of file

/** An AutoCAD export is a PDF; the image types are for a photo of a printout. */
const SUPPORTED_DOCUMENT_TYPES = new Set([
  "application/pdf",
  "image/png",
  "image/jpeg",
  "image/webp",
  "image/heic",
]);

function createGeminiClient({
  apiKey = process.env.GEMINI_API_KEY,
  model: requestedModel = process.env.GEMINI_MODEL || DEFAULT_MODEL,
  fetchImpl = globalThis.fetch,
} = {}) {
  if (typeof fetchImpl !== "function") throw new Error("Gemini requires Node.js 20 or newer.");
  const model = resolveModel(requestedModel);

  return {
    configured: Boolean(apiKey),
    model,

    async generate(prompt, { systemInstruction } = {}) {
      if (!apiKey) {
        const error = new Error("Gemini is not configured on this server.");
        error.statusCode = 503;
        throw error;
      }
      if (typeof prompt !== "string" || !prompt.trim()) {
        const error = new Error("A prompt is required.");
        error.statusCode = 400;
        throw error;
      }
      if (prompt.length > 20_000) {
        const error = new Error("The prompt is too long.");
        error.statusCode = 413;
        throw error;
      }

      const body = { contents: [{ role: "user", parts: [{ text: prompt.trim() }] }] };
      if (systemInstruction) {
        body.systemInstruction = { parts: [{ text: systemInstruction }] };
      }

      const response = await fetchImpl(
        `${GEMINI_BASE_URL}/${encodeURIComponent(model)}:generateContent`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": apiKey,
          },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(30_000),
        }
      );
      const result = await response.json().catch(() => ({}));
      if (!response.ok) {
        const error = new Error(geminiErrorMessage(result));
        error.statusCode = response.status === 429 ? 429 : 502;
        throw error;
      }
      const text = (result.candidates?.[0]?.content?.parts || [])
        .map((part) => part.text || "")
        .join("")
        .trim();
      if (!text) {
        const error = new Error("Gemini returned no text.");
        error.statusCode = 502;
        throw error;
      }
      return { text, model, usage: result.usageMetadata || null };
    },

    /** Read a document and return JSON matching `schema`.
     *
     * Gemini takes a PDF as an inline part and reads it natively — pages,
     * tables and the drawing itself — so an AutoCAD scheme does not have to be
     * rasterised or OCR'd first. JSON mode makes the model answer with JSON
     * instead of prose that would have to be parsed out of a code fence. The
     * exact shape is supplied in the extraction prompt and validated by the
     * server; sending the full schema here can exceed Gemini's structured-
     * output complexity limit before the PDF is even read.
     *
     * The timeout is far longer than `generate`'s: a multi-page A1 scheme is a
     * lot of tokens and routinely takes the better part of a minute.
     */
    async readDocument({ data, mimeType, prompt, systemInstruction }) {
      if (!apiKey) {
        const error = new Error("Gemini is not configured on this server.");
        error.statusCode = 503;
        throw error;
      }
      if (typeof data !== "string" || !data) {
        const error = new Error("A base64 document is required.");
        error.statusCode = 400;
        throw error;
      }
      if (!SUPPORTED_DOCUMENT_TYPES.has(mimeType)) {
        const error = new Error(`Unsupported document type: ${mimeType}`);
        error.statusCode = 415;
        throw error;
      }
      if (data.length > MAX_DOCUMENT_BASE64) {
        const error = new Error("That file is too large to read. Keep it under 8 MB.");
        error.statusCode = 413;
        throw error;
      }

      const body = {
        contents: [{
          role: "user",
          parts: [
            {
              inline_data: { mime_type: mimeType, data },
            },
            { text: prompt },
          ],
        }],
        generationConfig: {
          responseMimeType: "application/json",
        },
      };
      if (systemInstruction) {
        body.systemInstruction = { parts: [{ text: systemInstruction }] };
      }

      const response = await fetchImpl(
        `${GEMINI_BASE_URL}/${encodeURIComponent(model)}:generateContent`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(120_000),
        }
      );
      const result = await response.json().catch(() => ({}));
      if (!response.ok) {
        const error = new Error(geminiErrorMessage(result));
        error.statusCode = response.status === 429 ? 429 : 502;
        throw error;
      }

      const text = (result.candidates?.[0]?.content?.parts || [])
        .map((part) => part.text || "")
        .join("")
        .trim();
      if (!text) {
        const error = new Error("Gemini could not read that document.");
        error.statusCode = 502;
        throw error;
      }
      try {
        return { data: JSON.parse(text), model, usage: result.usageMetadata || null };
      } catch {
        const error = new Error("Gemini returned a malformed reading of that document.");
        error.statusCode = 502;
        throw error;
      }
    },
  };
}

module.exports = {
  createGeminiClient,
  DEFAULT_MODEL,
  MAX_DOCUMENT_BASE64,
  resolveModel,
  SUPPORTED_DOCUMENT_TYPES,
};
