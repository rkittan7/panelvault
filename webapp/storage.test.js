const assert = require("node:assert/strict");
const http = require("node:http");
const test = require("node:test");

const { SupabaseStorage, canonicalJSON, createStorage } = require("./storage");

function fakeSupabase(initialState = null) {
  let state = initialState || { companies: {} };
  let version = 1;
  const requests = [];
  const server = http.createServer(async (req, res) => {
    let raw = "";
    for await (const chunk of req) raw += chunk;
    requests.push({ method: req.method, url: req.url, headers: req.headers, raw });
    res.setHeader("Content-Type", "application/json");
    if (req.method === "GET") {
      res.end(JSON.stringify([{ state, version }]));
      return;
    }
    const body = JSON.parse(raw);
    if (body.expected_version !== version) {
      res.statusCode = 409;
      res.end(JSON.stringify({ message: "state conflict" }));
      return;
    }
    state = body.new_state;
    version += 1;
    res.end(JSON.stringify(version));
  });
  return { server, requests, getState: () => state };
}

async function listen(server) {
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  return `http://127.0.0.1:${server.address().port}`;
}

test("Supabase storage loads and updates the private state row", async (t) => {
  const fake = fakeSupabase();
  const url = await listen(fake.server);
  t.after(() => fake.server.close());
  const storage = new SupabaseStorage(url, "test-service-role-key");

  assert.deepEqual(await storage.load(), { companies: {} });
  await storage.save({ companies: { ABC123: { name: "Kittan Electric" } } });

  assert.equal(fake.requests.length, 2);
  assert.equal(fake.requests[0].method, "GET");
  assert.equal(fake.requests[1].headers.apikey, "test-service-role-key");
  assert.equal(fake.requests[1].headers.authorization, "Bearer test-service-role-key");
  assert.match(fake.requests[1].url, /rpc\/panelvault_save_state/);
  assert.equal(fake.getState().companies.ABC123.name, "Kittan Electric");
});

test("Supabase storage rejects stale writes from another server instance", async (t) => {
  const fake = fakeSupabase();
  const url = await listen(fake.server);
  t.after(() => fake.server.close());
  const first = new SupabaseStorage(url, "key");
  const second = new SupabaseStorage(url, "key");
  await first.load();
  await second.load();
  await first.save({ companies: { FIRST: {} } });
  await assert.rejects(() => second.save({ companies: { SECOND: {} } }), /Supabase returned 409/);
  assert.deepEqual(fake.getState(), { companies: { FIRST: {} } });
});

test("storage configuration requires the URL and key together", () => {
  assert.throws(
    () => createStorage({ dataDir: "/tmp/unused", env: { SUPABASE_URL: "https://example.supabase.co" } }),
    /Set both SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY/
  );
});

test("canonical JSON ignores object key order for import verification", () => {
  assert.equal(
    canonicalJSON({ companies: { B: { name: "two" }, A: { name: "one" } } }),
    canonicalJSON({ companies: { A: { name: "one" }, B: { name: "two" } } })
  );
});

test("Supabase service-role transport rejects non-loopback HTTP", () => {
  assert.throws(
    () => new SupabaseStorage("http://example.com", "secret"),
    /SUPABASE_URL must use HTTPS/
  );
});
