const assert = require("node:assert/strict");
const { PassThrough } = require("node:stream");
const { setTimeout: delay } = require("node:timers/promises");
const test = require("node:test");
const { readJSONBody } = require("./body");

test("a continuously arriving upload may take longer than one idle window", async () => {
  const request = new PassThrough();
  const body = readJSONBody(request, { idleTimeout: 200 });

  request.write('{"document":"');
  await delay(110);
  request.write("still arriving");
  await delay(110);
  request.end('"}');

  assert.deepEqual(await body, { document: "still arriving" });
});

test("a request with no incoming data still times out", async () => {
  const request = new PassThrough();
  const body = readJSONBody(request, { idleTimeout: 20 });

  await assert.rejects(body, /request body timed out/i);
  request.end();
});
