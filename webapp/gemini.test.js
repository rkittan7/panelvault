const assert = require("node:assert/strict");
const test = require("node:test");
const { createGeminiClient, DEFAULT_MODEL, resolveModel } = require("./gemini");

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

test("a retired Flash environment override falls forward to the supported model", async () => {
  let requestedURL = "";
  const client = createGeminiClient({
    apiKey: "test-key",
    model: "models/gemini-2.5-flash",
    fetchImpl: async (url) => {
      requestedURL = url;
      return new Response(JSON.stringify({
        candidates: [{ content: { parts: [{ text: "Ready" }] } }],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    },
  });

  const result = await client.generate("Read this board");
  assert.equal(resolveModel("gemini-2.5-flash"), DEFAULT_MODEL);
  assert.equal(client.model, DEFAULT_MODEL);
  assert.equal(result.model, DEFAULT_MODEL);
  assert.match(requestedURL, /gemini-3\.6-flash:generateContent$/);
});

test("reading a document sends it inline and returns parsed JSON", async () => {
  let request;
  const client = createGeminiClient({
    apiKey: "test-key",
    model: "test-model",
    fetchImpl: async (url, options) => {
      request = { url, body: JSON.parse(options.body) };
      return new Response(JSON.stringify({
        candidates: [{ content: { parts: [{ text: '{"board":{"number":"3918.24-1"}}' }] } }],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    },
  });

  const result = await client.readDocument({
    data: "JVBERi0=",
    mimeType: "application/pdf",
    prompt: "Read this scheme",
  });

  assert.equal(result.data.board.number, "3918.24-1");
  assert.equal(request.body.contents[0].parts[0].inline_data.mime_type, "application/pdf");
  assert.equal(request.body.contents[0].parts[0].inline_data.data, "JVBERi0=");
  assert.deepEqual(request.body.contents[0].parts[0].mediaResolution, {
    level: "MEDIA_RESOLUTION_MEDIUM",
  });
  // Gemini 3 is tuned for its default temperature; the no-guess rule belongs
  // in the extraction instruction and semantic validation instead.
  assert.equal(request.body.generationConfig.temperature, undefined);
  assert.equal(request.body.generationConfig.responseMimeType, "application/json");
  assert.equal(request.body.generationConfig.thinkingConfig.thinkingLevel, "low");
  // The detailed shape lives in the extraction prompt. Large structured-output
  // schemas are rejected by some Gemini models before they inspect the PDF.
  assert.equal(request.body.generationConfig.responseJsonSchema, undefined);
  assert.equal(request.body.generationConfig.responseSchema, undefined);
});

test("a document timeout becomes an actionable gateway-timeout error", async () => {
  const client = createGeminiClient({
    apiKey: "test-key",
    fetchImpl: async () => {
      throw new DOMException("The operation was aborted due to timeout", "TimeoutError");
    },
  });

  await assert.rejects(
    () => client.readDocument({ data: "AAAA", mimeType: "application/pdf", prompt: "read" }),
    (error) => error.statusCode === 504 && /only this board's pages/i.test(error.message),
  );
});

test("Gemini field violations are included when a request is rejected", async () => {
  const client = createGeminiClient({
    apiKey: "test-key",
    fetchImpl: async () => new Response(JSON.stringify({
      error: {
        message: "Request contains an invalid argument.",
        details: [{
          fieldViolations: [{
            field: "generation_config.example",
            description: "Cannot find field.",
          }],
        }],
      },
    }), { status: 400, headers: { "Content-Type": "application/json" } }),
  });

  await assert.rejects(
    () => client.readDocument({ data: "AAAA", mimeType: "application/pdf", prompt: "read" }),
    /generation_config\.example: Cannot find field/,
  );
});

test("reading a document rejects unsupported types and oversized files", async () => {
  const client = createGeminiClient({ apiKey: "test-key", fetchImpl: async () => {
    throw new Error("must not reach the network");
  } });

  await assert.rejects(
    () => client.readDocument({ data: "AAAA", mimeType: "application/zip", prompt: "x" }),
    { statusCode: 415 },
  );
  await assert.rejects(
    () => client.readDocument({ data: "A".repeat(11_000_001), mimeType: "application/pdf", prompt: "x" }),
    { statusCode: 413 },
  );
});

test("a malformed reading is reported rather than returned half-parsed", async () => {
  const client = createGeminiClient({
    apiKey: "test-key",
    fetchImpl: async () => new Response(JSON.stringify({
      candidates: [{ content: { parts: [{ text: "sorry, I could not read that" }] } }],
    }), { status: 200, headers: { "Content-Type": "application/json" } }),
  });

  await assert.rejects(
    () => client.readDocument({ data: "AAAA", mimeType: "application/pdf", prompt: "x" }),
    { statusCode: 502 },
  );
});
