const DEFAULT_MODEL = "gemini-3.6-flash";
const GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models";

function createGeminiClient({
  apiKey = process.env.GEMINI_API_KEY,
  model = process.env.GEMINI_MODEL || DEFAULT_MODEL,
  fetchImpl = globalThis.fetch,
} = {}) {
  if (typeof fetchImpl !== "function") throw new Error("Gemini requires Node.js 20 or newer.");

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
        const error = new Error(result.error?.message || "Gemini request failed.");
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
  };
}

module.exports = { createGeminiClient, DEFAULT_MODEL };
