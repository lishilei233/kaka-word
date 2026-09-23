import assert from "node:assert/strict";
import test from "node:test";
import { hasRecognizableSize } from "./object-size.js";
import { QwenVisionProvider } from "./providers/qwen.js";
import { GeminiVisionProvider } from "./providers/gemini.js";
import type { VisionInput } from "./types.js";

test("size thresholds include exact boundaries and reject small, thin and clipped boxes", () => {
  const check = (width: number, height: number, x = 0.2, y = 0.2) =>
    hasRecognizableSize({ box: { x, y, width, height } });
  assert.equal(check(0.05, 0.1), true);
  assert.equal(check(0.04999, 0.1), false);
  assert.equal(check(0.05001, 0.1), true);
  assert.equal(check(0.02, 0.5), true);
  assert.equal(check(0.01999, 0.5), false);
  assert.equal(check(0.5, 0.02), true);
  assert.equal(check(0.5, 0.01999), false);
  assert.equal(check(0.015, 0.8), false);
  assert.equal(check(0.08, 0.08), true);
  assert.equal(check(0, 1), false);
  assert.equal(check(0.5, 0.5, 0.99), false);
  assert.equal(check(0.5, 0.5, 0.8, 0.8), true);
  assert.equal(check(0.1, 0.1, 0.9, 0.9), true);
  assert.equal(check(0.5, 0.5, 1), false);
  assert.equal(check(NaN, 1), false);
});

const input: VisionInput = { image: new Uint8Array([1]), mimeType: "image/jpeg",
  imageWidth: 1000, imageHeight: 1000, language: "zh-CN", maxObjects: 4,
  captionStyle: "serious", masteredWords: [] };
const tiny = { id: "obj_01", english: "button", chinese: "纽扣", confidence: 0.9,
  bbox: [400, 400, 410, 410], example: "A button." };
const large = { id: "obj_02", english: "book", chinese: "书", confidence: 0.9,
  bbox: [100, 100, 800, 800], anchor: [200, 200], example: "A book." };

for (const mode of ["stream", "buffered", "regular"] as const) {
  for (const allTiny of [false, true]) {
    test(`Qwen ${mode} filters ${allTiny ? "all tiny objects" : "tiny objects without renumbering"} before output and review`, async (t) => {
      let calls = 0;
      const payload = { objects: allTiny ? [tiny] : [tiny, large], caption: "A book.", captionChinese: "一本书。", captionSentences: [{ english: "A book.", chinese: "一本书。" }] };
      t.mock.method(globalThis, "fetch", async () => {
        calls++;
        const content = JSON.stringify(payload);
        return mode === "stream"
          ? new Response('data: ' + JSON.stringify({ choices: [{ delta: { content }, finish_reason: "stop" }] }) + '\n\ndata: [DONE]\n\n',
              { headers: { "content-type": "text/event-stream" } })
          : Response.json({ choices: [{ message: { content }, finish_reason: "stop" }] });
      });
      const provider = new QwenVisionProvider({ apiKey: "test", apiHost: "https://example.test", model: "test" });
      const ids: string[] = [];
      const result = mode === "regular" ? await provider.analyze(input)
        : await provider.analyzeStream(input, (object) => { ids.push(object.id); });
      const expected = allTiny ? [] : ["obj_02"];
      assert.deepEqual(result.objects.map(object => object.id), expected);
      if (mode !== "regular") assert.deepEqual(ids, expected);
      assert.equal(calls, 1, "filtered objects must not trigger anchor review");
    });
  }
}

test("HTTP providers filter clipped and tiny boxes before overlap review", async (t) => {
  const object = { id: "book", english: "book", chinese: "书", confidence: 0.9,
    box: { x: 0.1, y: 0.1, width: 0.7, height: 0.7 }, anchor: { x: 0.2, y: 0.2 }, example: "A book." };
  t.mock.method(globalThis, "fetch", async () => Response.json({ candidates: [{ content: { parts: [{ text: JSON.stringify({
    imageWidth: 1000, imageHeight: 1000, objects: [object,
      { ...object, id: "tiny", box: { x: 0.195, y: 0.195, width: 0.01, height: 0.01 } },
      { ...object, id: "clipped", box: { x: 0.99, y: 0.1, width: 0.7, height: 0.7 } }],
    caption: "A book.", captionChinese: "一本书。", captionSentences: [{ english: "A book.", chinese: "一本书。" }],
  }) }] } }] }));
  const result = await new GeminiVisionProvider({ apiKey: "test", model: "test" }).analyze(input);
  assert.deepEqual(result.objects.map(object => object.id), ["book"]);
  assert.equal(result.objects[0].anchorNeedsReview, false);
});
