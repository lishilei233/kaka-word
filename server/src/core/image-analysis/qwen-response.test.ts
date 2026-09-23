import assert from "node:assert/strict";
import test from "node:test";
import { QwenResponseReader } from "./qwen-response.js";
import { QwenVisionProvider } from "./providers/qwen.js";
import type { VisionInput } from "./types.js";

const reader = () => new QwenResponseReader("text/event-stream", "request-123");
const chunk = (content: unknown, finish_reason: unknown = null) => JSON.stringify({ choices: [{ delta: { content }, finish_reason }] });

test("JSON mode stream accumulates fragments and ignores usage-only and role-only chunks", () => {
  const r = reader();
  r.push(chunk(null), true);
  r.push(chunk('{"objects":'), true);
  r.push(chunk('[],"caption":"杯子"}', "stop"), true);
  r.push(JSON.stringify({ choices: [], usage: { completion_tokens: 19 } }), true);
  assert.deepEqual(r.json(), { objects: [], caption: "杯子" });
});

test("empty completion reports safe diagnostic metadata instead of no JSON object", () => {
  const r = reader();
  r.push(chunk(null, "stop"), true);
  assert.throws(() => r.json(), (error: Error) => {
    assert.equal(error.name, "QwenResponseError");
    assert.match(error.message, /empty content/);
    assert.match(error.message, /request-123/);
    assert.match(error.message, /"contentLength":0/);
    assert.match(error.message, /"finishReason":"stop"/);
    return true;
  });
});

test("in-stream upstream errors preserve only code and request ID", () => {
  assert.throws(() => reader().push(JSON.stringify({ error: { code: "DataInspectionFailed", message: "private photo text" }, request_id: "upstream-42" }), true), (error: Error) => {
    assert.match(error.message, /DataInspectionFailed/);
    assert.match(error.message, /upstream-42/);
    assert.doesNotMatch(error.message, /private photo text/);
    return true;
  });
});

for (const reason of ["length", "content_filter", "tool_calls"]) {
  test(`abnormal finish reason ${reason} is not treated as successful JSON`, () => {
    assert.throws(() => reader().push(chunk('{}', reason), true), new RegExp(reason));
  });
}

for (const content of ['{"objects":', 'private non-JSON text', 'null', '[]', '```json\n{}\n```']) {
  test(`invalid JSON-mode content ${JSON.stringify(content)} is rejected without logging content`, () => {
    const r = reader();
    r.push(chunk(content), true);
    assert.throws(() => r.json(), (error: Error) => {
      assert.match(error.message, /JSON/);
      assert.doesNotMatch(error.message, /private non-JSON text/);
      return true;
    });
  });
}

test("unsupported envelopes and refusals are diagnosed", () => {
  assert.throws(() => reader().push('{"output":{}}', true), /no choices/);
  assert.throws(() => reader().push('not JSON', true), /invalid response envelope/);
  assert.throws(() => reader().push('{"choices":[{"delta":{"refusal":"private"}}]}', true), /refused/);
});

test("buffered JSON response to stream request still emits validated objects", async (t) => {
  let calls = 0;
  t.mock.method(globalThis, "fetch", async (_url: unknown, init: RequestInit) => {
    calls++;
    const request = JSON.parse(String(init.body));
    assert.deepEqual(request.response_format, { type: "json_object" });
    assert.equal(request.enable_thinking, false);
    assert.equal(request.stream, true);
    assert.match(request.messages[0].content[0].text, /JSON/);
    return Response.json({ choices: [{ finish_reason: "stop", message: { content: JSON.stringify({ objects: [
      { id: "book", english: "book", chinese: "书", confidence: 0.9, bbox: [100, 100, 800, 800], anchor: [200, 200], example: "A book." },
    ], caption: "A book.", captionChinese: "一本书。", captionSentences: [{ english: "A book.", chinese: "一本书。" }] }) } }] });
  });
  const input: VisionInput = { image: new Uint8Array([1]), mimeType: "image/jpeg", imageWidth: 100, imageHeight: 100,
    language: "zh-CN", maxObjects: 4, captionStyle: "serious", masteredWords: [] };
  const ids: string[] = [];
  const result = await new QwenVisionProvider({ apiKey: "test", apiHost: "https://example.test", model: "qwen3.8-flash" })
    .analyzeStream(input, (object) => { ids.push(object.id); });
  assert.deepEqual(ids, ["book"]);
  assert.equal(result.objects.length, 1);
  assert.equal(calls, 1);
});

const retryInput: VisionInput = { image: new Uint8Array([1]), mimeType: "image/jpeg", imageWidth: 100, imageHeight: 100,
  language: "zh-CN", maxObjects: 4, captionStyle: "serious", masteredWords: [] };
const validResult = { objects: [{ id: "book", english: "book", chinese: "书", confidence: 0.9,
  bbox: [100, 100, 800, 800], anchor: [200, 200], example: "A book." }], caption: "A book.", captionChinese: "一本书。", captionSentences: [{ english: "A book.", chinese: "一本书。" }] };
const completion = (content: string) => Response.json({ choices: [{ message: { content }, finish_reason: "stop" }] });
const sse = (content: string, reason = "stop") => new Response(`data: ${chunk(content, reason)}\n\ndata: [DONE]\n\n`, { headers: { "content-type": "text/event-stream" } });
const provider = () => new QwenVisionProvider({ apiKey: "test", apiHost: "https://example.test", model: "qwen3.8-flash" });

for (const invalid of ["[]", "\"\"", "", "{}", '{"objects":']) {
  test(`invalid initial result ${JSON.stringify(invalid)} retries once while preserving streaming`, async (t) => {
    let calls = 0;
    t.mock.method(globalThis, "fetch", async (_url: unknown, init: RequestInit) => {
      const request = JSON.parse(String(init.body));
      calls++;
      assert.equal(request.stream, true);
      assert.deepEqual(request.response_format, { type: "json_object" });
      if (calls === 1) return sse(invalid);
      assert.equal(request.messages[0].role, "system");
      assert.match(request.messages[0].content, /top-level array/);
      assert.equal(request.messages[1].content[1].type, "image_url");
      return completion(JSON.stringify(validResult));
    });
    const ids: string[] = [];
    const result = await provider().analyzeStream(retryInput, (object) => { ids.push(object.id); });
    assert.equal(calls, 2);
    assert.deepEqual(ids, ["book"]);
    assert.equal(result.objects.length, 1);
  });
}

test("second invalid result fails without further requests", async (t) => {
  let calls = 0;
  t.mock.method(globalThis, "fetch", async () => ++calls === 1 ? sse("[]") : completion("[]"));
  await assert.rejects(provider().analyzeStream(retryInput, () => assert.fail("No invalid objects should be emitted")), /non-object JSON/);
  assert.equal(calls, 2);
});

test("invalid non-stream result also gets only one retry", async (t) => {
  let calls = 0;
  t.mock.method(globalThis, "fetch", async () => completion(++calls === 1 ? "[]" : JSON.stringify(validResult)));
  assert.equal((await provider().analyze(retryInput)).objects.length, 1);
  assert.equal(calls, 2);
});

for (const reason of ["content_filter", "length"]) {
  test(`${reason} completion is not retried`, async (t) => {
    let calls = 0;
    t.mock.method(globalThis, "fetch", async () => { calls++; return sse("", reason); });
    await assert.rejects(provider().analyzeStream(retryInput, () => {}), new RegExp(reason));
    assert.equal(calls, 1);
  });
}

test("partially emitted recognition is never retried", async (t) => {
  let calls = 0;
  t.mock.method(globalThis, "fetch", async () => { calls++; return sse(JSON.stringify(validResult).slice(0, -1)); });
  const ids: string[] = [];
  await assert.rejects(provider().analyzeStream(retryInput, (object) => { ids.push(object.id); }), /incomplete JSON/);
  assert.equal(calls, 1);
  assert.deepEqual(ids, ["book"]);
});

test("caller cancellation prevents retry", async (t) => {
  let calls = 0;
  const controller = new AbortController();
  t.mock.method(globalThis, "fetch", async () => { calls++; controller.abort(); return sse("[]"); });
  await assert.rejects(provider().analyzeStream({ ...retryInput, signal: controller.signal }, () => {}));
  assert.equal(calls, 1);
});

test("upstream errors are not retried", async (t) => {
  let calls = 0;
  t.mock.method(globalThis, "fetch", async () => {
    calls++;
    return new Response('data: {"error":{"code":"InsufficientQuota"}}\n\n', { headers: { "content-type": "text/event-stream" } });
  });
  await assert.rejects(provider().analyzeStream(retryInput, () => {}), /InsufficientQuota/);
  assert.equal(calls, 1);
});

test("retry emits a complete object before the upstream stream finishes", async (t) => {
  let calls = 0;
  let finishStream!: () => void;
  let firstObject!: () => void;
  const received = new Promise<void>((resolve) => { firstObject = resolve; });
  const encoder = new TextEncoder();
  t.mock.method(globalThis, "fetch", async (_url: unknown, init: RequestInit) => {
    calls++;
    assert.equal(JSON.parse(String(init.body)).stream, true);
    if (calls === 1) return sse("[]");
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        const prefix = '{"objects":[' + JSON.stringify(validResult.objects[0]);
        controller.enqueue(encoder.encode(`data: ${chunk(prefix)}\n\n`));
        finishStream = () => {
          const suffix = '],"caption":"A book.","captionChinese":"一本书。","captionSentences":[{"english":"A book.","chinese":"一本书。"}]}';
          controller.enqueue(encoder.encode(`data: ${chunk(suffix, "stop")}\n\ndata: [DONE]\n\n`));
          controller.close();
        };
      },
    });
    return new Response(body, { headers: { "content-type": "text/event-stream" } });
  });
  const ids: string[] = [];
  let completed = false;
  const result = provider().analyzeStream(retryInput, (object) => {
    ids.push(object.id);
    firstObject();
  }).then((value) => { completed = true; return value; });
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    await Promise.race([received, new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new Error("Object was buffered until stream completion")), 2000);
    })]);
    assert.equal(completed, false);
    assert.deepEqual(ids, ["book"]);
  } finally {
    if (timer) clearTimeout(timer);
    finishStream?.();
  }
  assert.equal((await result).objects.length, 1);
  assert.deepEqual(ids, ["book"]);
  assert.equal(calls, 2);
});
