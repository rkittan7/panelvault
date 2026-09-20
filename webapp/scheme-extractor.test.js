const assert = require("node:assert/strict");
const test = require("node:test");
const { createSchemeExtractorClient, DEFAULT_BASE_URL } = require("./scheme-extractor");

function stub(handler) {
  const calls = [];
  const client = createSchemeExtractorClient({
    baseUrl: "http://extractor.test",
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return handler(url, options);
    },
  });
  return { client, calls };
}

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

test("submitting a scheme posts the base64 document and returns the job", async () => {
  const { client, calls } = stub(() => json({ job_id: "job_abc", status: "queued" }, 202));
  const job = await client.submit({ fileName: "4382.26-8.pdf", data: " JVBERi0x " });

  assert.deepEqual(job, { job_id: "job_abc", status: "queued" });
  assert.equal(calls[0].url, "http://extractor.test/extract");
  const body = JSON.parse(calls[0].options.body);
  assert.equal(body.data, "JVBERi0x");
  assert.equal(body.fileName, "4382.26-8.pdf");
});

test("a per-run model override travels to the service", async () => {
  const { client, calls } = stub(() => json({ job_id: "job_abc", status: "queued" }, 202));
  await client.submit({ data: "JVBERi0x", models: { audit: "claude-sonnet-5" }, useBatch: false });

  const body = JSON.parse(calls[0].options.body);
  assert.deepEqual(body.models, { audit: "claude-sonnet-5" });
  assert.equal(body.use_batch, false);
});

test("an empty document is refused before it reaches the service", async () => {
  const { client, calls } = stub(() => json({}));
  await assert.rejects(() => client.submit({ data: "  " }), /Attach the scheme PDF/);
  assert.equal(calls.length, 0);
});

test("polling a job returns its progress", async () => {
  const { client, calls } = stub(() => json({ job_id: "job_abc", status: "running", progress: 0.42 }));
  const status = await client.job("job_abc");

  assert.equal(status.progress, 0.42);
  assert.equal(calls[0].url, "http://extractor.test/jobs/job_abc");
});

test("a job id is escaped into the path", async () => {
  const { client, calls } = stub(() => json({ status: "done" }));
  await client.job("../health");
  assert.equal(calls[0].url, "http://extractor.test/jobs/..%2Fhealth");
});

test("an unreachable sidecar reports 503, not a bad request", async () => {
  const client = createSchemeExtractorClient({
    baseUrl: "http://extractor.test",
    fetchImpl: async () => { throw new TypeError("fetch failed"); },
  });
  await assert.rejects(() => client.job("job_abc"), (error) => {
    assert.equal(error.statusCode, 503);
    assert.match(error.message, /not reachable/);
    return true;
  });
});

test("a slow sidecar reports 504", async () => {
  const client = createSchemeExtractorClient({
    baseUrl: "http://extractor.test",
    fetchImpl: async () => { const error = new Error("timed out"); error.name = "TimeoutError"; throw error; },
  });
  await assert.rejects(() => client.job("job_abc"), (error) => {
    assert.equal(error.statusCode, 504);
    return true;
  });
});

test("the service's own message survives, including FastAPI's field errors", async () => {
  const plain = stub(() => json({ detail: "That file is not a PDF." }, 415));
  await assert.rejects(() => plain.client.job("job_abc"), /That file is not a PDF/);

  const validation = stub(() => json({ detail: [{ msg: "field required", loc: ["body", "data"] }] }, 422));
  await assert.rejects(() => validation.client.job("job_abc"), /field required/);
});

test("a missing job stays a 404 rather than becoming a gateway error", async () => {
  const { client } = stub(() => json({ detail: "No such job." }, 404));
  await assert.rejects(() => client.job("job_gone"), (error) => {
    assert.equal(error.statusCode, 404);
    return true;
  });
});

test("the workbook comes back as bytes with its spreadsheet type", async () => {
  const { client } = stub(() => new Response(Buffer.from("PK-xlsx-bytes"), {
    status: 200,
    headers: { "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" },
  }));
  const book = await client.workbook("job_abc");

  assert.ok(Buffer.isBuffer(book.body));
  assert.match(book.contentType, /spreadsheetml\.sheet$/);
});

test("the default base url points at the sidecar, not at a public host", () => {
  assert.match(DEFAULT_BASE_URL, /^http:\/\/127\.0\.0\.1:/);
});
