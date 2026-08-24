import assert from "node:assert/strict";
import test from "node:test";
import { ObjectArrayStreamParser, readSSEData } from "./streaming-json.js";

test("extracts complete objects across arbitrary JSON fragments", () => {
  const parser = new ObjectArrayStreamParser();
  const fragments = [
    '{"objects":[{"id":"one","example":"brace: }',
    '\\" still text"},{"id":"two","nested":{"value":',
    '2}}],"other":true}',
  ];

  const objects = fragments.flatMap((fragment) => parser.push(fragment));
  assert.deepEqual(objects, [
    { id: "one", example: 'brace: }" still text' },
    { id: "two", nested: { value: 2 } },
  ]);
});

test("decodes SSE data split across line and multibyte boundaries", async () => {
  const encoded = new TextEncoder().encode("event: object\r\ndata: {\"chinese\":\"杯子\"}\r\n\r\ndata: [DONE]\n\n");
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const byte of encoded) controller.enqueue(Uint8Array.of(byte));
      controller.close();
    },
  });

  const payloads: string[] = [];
  for await (const payload of readSSEData(body)) payloads.push(payload);
  assert.deepEqual(payloads, ['{"chinese":"杯子"}', "[DONE]"]);
});
