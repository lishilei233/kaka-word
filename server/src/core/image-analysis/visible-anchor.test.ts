import assert from "node:assert/strict";
import test from "node:test";
import { normalizeVisibleAnchor, markSuspiciousAnchors } from "./visible-anchor.js";
import { QwenVisionProvider } from "./providers/qwen.js";
import { learningObjectSchema, type VisionInput } from "./types.js";

const object = (id = "table") => learningObjectSchema.parse({ id, english: id, chinese: "物体", confidence: 0.9,
  box: { x: 0.1, y: 0.1, width: 0.8, height: 0.8 }, anchor: { x: 0.5, y: 0.5 }, example: "A table." });

test("visible points retain provenance; invalid and missing points are explicit fallbacks", () => {
  assert.equal(normalizeVisibleAnchor(object()).anchorSource, "ai");
  for (const anchor of [undefined, { x: 0, y: 0 }, { x: NaN, y: 0.5 }, { x: 2, y: 0.5 }]) {
    const result = normalizeVisibleAnchor({ ...object(), anchor });
    assert.equal(result.anchorSource, "centerFallback");
    assert.equal(result.anchorNeedsReview, true);
    assert.deepEqual(result.anchor, { x: 0.5, y: 0.5 });
  }
  assert.equal(normalizeVisibleAnchor({ ...object(), anchorSource: "centerFallback" }).anchorSource, "centerFallback");
});

test("book over table marks table as suspicious without moving its point geometrically", () => {
  const table = normalizeVisibleAnchor(object());
  const book = normalizeVisibleAnchor({ ...object("book"), box: { x: 0.4, y: 0.4, width: 0.2, height: 0.2 } });
  const marked = markSuspiciousAnchors([table, book]);
  assert.equal(marked[0].anchorNeedsReview, true);
  assert.equal(marked[1].anchorNeedsReview, false);
  assert.deepEqual(marked[0].anchor, table.anchor);
});

const input: VisionInput = { image: new Uint8Array([1]), mimeType: "image/jpeg", imageWidth: 100, imageHeight: 100,
  language: "zh-CN", maxObjects: 4, captionStyle: "serious", masteredWords: [] };
const raw = { objects: [{ id: "table", english: "table", chinese: "桌子", confidence: 0.9,
  bbox: [100, 100, 900, 900], anchor: [500, 500], example: "A table." },
  { id: "book", english: "book", chinese: "书", confidence: 0.9,
    bbox: [400, 400, 600, 600], anchor: [500, 500], example: "A book." }], caption: "A book on a table.", captionChinese: "桌上的书。", captionSentences: [{ english: "A book on a table.", chinese: "桌上的书。" }] };
const reply = (content: unknown) => Response.json({ choices: [{ message: { content: JSON.stringify(content) } }] });

for (const stream of [false, true]) {
  test(`Qwen ${stream ? "stream" : "response"} reviews overlapping points once and preserves boxes`, async (t) => {
    let calls = 0;
    t.mock.method(globalThis, "fetch", async (_url: unknown, options: RequestInit) => {
      calls++;
      if (calls === 1) {
        if (!stream) return reply(raw);
        return new Response(`data: ${JSON.stringify({ choices: [{ delta: { content: JSON.stringify(raw) } }] })}\n\ndata: [DONE]\n\n`);
      }
      assert.match(String(options.body), /exposed wood/);
      return reply({ points: [{ id: "table", anchor: [800, 800], visible: true }] });
    });
    const provider = new QwenVisionProvider({ apiKey: "test", apiHost: "https://example.test", model: "test" });
    const streamed: unknown[] = [];
    const result = stream ? await provider.analyzeStream(input, (object) => { streamed.push(object); }) : await provider.analyze(input);
    assert.equal(calls, 2);
    assert.equal(result.objects[0].anchorNeedsReview, false);
    assert.equal(result.objects[0].anchorSource, "ai");
    assert.deepEqual(result.objects[0].anchor, { x: 800 / 999, y: 800 / 999 });
    assert.equal(result.objects[0].box.x, 100 / 999);
    if (stream) assert.equal(streamed.length, 2);
  });
}

for (const review of ["failure", "outside", "invisible", "duplicate", "malformed"] as const) {
  test(`Qwen ${review} review preserves result and review flag`, async (t) => {
    let calls = 0;
    t.mock.method(globalThis, "fetch", async () => {
      if (++calls === 1) return reply(raw);
      if (review === "failure") throw new Error("network failed");
      if (review === "malformed") return reply({ points: "invalid" });
      const point = { id: "table", anchor: review === "outside" ? [0, 0] : [800, 800], visible: review !== "invisible" };
      return reply({ points: review === "duplicate" ? [point, point] : [point] });
    });
    const result = await new QwenVisionProvider({ apiKey: "test", apiHost: "https://example.test", model: "test" }).analyze(input);
    assert.equal(calls, 2);
    assert.equal(result.objects[0].anchorNeedsReview, true);
    assert.deepEqual(result.objects[0].anchor, { x: 500 / 999, y: 500 / 999 });
  });
}

test("valid L-arm anchor needs no second request", async (t) => {
  let calls = 0;
  t.mock.method(globalThis, "fetch", async () => {
    calls++;
    return reply({ ...raw, objects: [{ ...raw.objects[0], anchor: [200, 800] }] });
  });
  const result = await new QwenVisionProvider({ apiKey: "test", apiHost: "https://example.test", model: "test" }).analyze(input);
  assert.equal(calls, 1);
  assert.equal(result.objects[0].anchorSource, "ai");
  assert.deepEqual(result.objects[0].anchor, { x: 200 / 999, y: 800 / 999 });
});

test("out-of-range Qwen point is not silently clamped into an AI anchor", async (t) => {
  let calls = 0;
  t.mock.method(globalThis, "fetch", async () => {
    if (++calls === 1) return reply({ ...raw, objects: [{ ...raw.objects[0], anchor: [-10, 500] }] });
    return reply({ points: [{ id: "table", visible: false }] });
  });
  const result = await new QwenVisionProvider({ apiKey: "test", apiHost: "https://example.test", model: "test" }).analyze(input);
  assert.equal(result.objects[0].anchorSource, "centerFallback");
  assert.equal(result.objects[0].anchorNeedsReview, true);
  assert.equal(calls, 2);
});

test("caller cancellation is not swallowed by best-effort review", async (t) => {
  const controller = new AbortController();
  let calls = 0;
  t.mock.method(globalThis, "fetch", async () => {
    if (++calls === 1) return reply(raw);
    controller.abort();
    throw new Error("cancelled");
  });
  await assert.rejects(new QwenVisionProvider({ apiKey: "test", apiHost: "https://example.test", model: "test" })
    .analyze({ ...input, signal: controller.signal }), /cancelled/);
  assert.equal(calls, 2);
});
