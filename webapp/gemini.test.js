const assert = require("node:assert/strict");
const test = require("node:test");
const { createGeminiClient } = require("./gemini");

test("Gemini client keeps the key in a header and returns generated text", async () => {
  let request;
  const client = createGeminiClient({
    apiKey: "test-key",
    model: "test-model",
    fetchImpl: async (url, options) => {
      request = { url, options };
      return new Response(JSON.stringify({
        candidates: [{ content: { parts: [{ text: "Panel result" }] } }],
        usageMetadata: { totalTokenCount: 12 },
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    },
  });

  const result = await client.generate("Check this panel");
  assert.equal(result.text, "Panel result");
  assert.match(request.url, /test-model:generateContent$/);
  assert.equal(request.options.headers["x-goog-api-key"], "test-key");
  assert.doesNotMatch(request.url, /test-key/);
});

test("Gemini client fails safely when no key is configured", async () => {
  const client = createGeminiClient({ apiKey: "" });
  await assert.rejects(() => client.generate("hello"), { statusCode: 503 });
});
