import { test } from 'node:test';
import assert from 'node:assert/strict';
import { forwardRecognition } from './recognition.server.ts';
const result = { imageWidth: 800, imageHeight: 600, objects: [], caption: 'A quiet room.', captionChinese: '安静的房间。', captionStyle: 'serious' };

test('forwards multipart image and existing access headers, decodes chunked SSE with photo descriptions', async () => {
    const transport: typeof fetch = async (input, init) => {
        assert.equal(input, 'http://127.0.0.1:8787/v1/analyze');
        const headers = new Headers(init?.headers);
        assert.equal(headers.get('authorization'), 'Bearer test-access');
        assert.equal(headers.get('x-devicecheck-token'), 'test-device');
        assert.match(headers.get('x-operation-id')!, /^[a-f0-9-]{36}$/);
        assert.equal(headers.has('content-type'), false);
        const form = init?.body as FormData;
        assert.equal(form.get('maxObjects'), '8');
        assert.equal((form.get('image') as Blob).type, 'image/jpeg');
        const text = `event: started\r\ndata: {"imageWidth":800}\r\n\r\nevent: complete\r\ndata: ${JSON.stringify(result)}\r\n\r\nevent: quota\r\ndata: {"remaining":5}\r\n\r\n`;
        const data = new TextEncoder().encode(text);
        return new Response(new ReadableStream({ start(controller) { for (let i=0;i<data.length;i+=7) controller.enqueue(data.slice(i,i+7)); controller.close(); } }), { headers: { 'content-type': 'text/event-stream' } });
    };
    const response = await forwardRecognition(new Uint8Array([1,2]), 8, { baseURL: 'http://127.0.0.1:8787/', accessToken: 'test-access', deviceToken: 'test-device' }, undefined, transport);
    assert.deepEqual(await response.json(), result);
});

test('preserves server authentication, quota and rate-limit errors without retrying', async () => {
    for (const status of [401,402,429]) {
        let calls = 0;
        const response = await forwardRecognition(new Uint8Array(), 8, { baseURL: 'http://localhost:8787' }, undefined, async () => {
            calls++;
            return Response.json({ error: 'SERVER_CODE', message: '原服务错误提示' }, { status, headers: { 'retry-after': '12' } });
        });
        assert.equal(calls, 1); assert.equal(response.status, status);
        assert.equal(response.headers.get('retry-after'), '12');
        assert.equal((await response.json()).message, '原服务错误提示');
    }
});

test('rejects interrupted or failed streams instead of treating partial objects as a result', async () => {
    const transport: typeof fetch = async () => new Response('event: object\ndata: {"id":"partial"}\n\n', { headers: { 'content-type': 'text/event-stream' } });
    await assert.rejects(() => forwardRecognition(new Uint8Array(), 8, { baseURL:'http://localhost:8787' }, undefined, transport), /中断/);
    const failed = await forwardRecognition(new Uint8Array(), 8, { baseURL:'http://localhost:8787' }, undefined, async () => new Response('event: error\ndata: {"error":"ANALYZE_FAILED","message":"请重试"}\n\n', {headers:{'content-type':'text/event-stream'}}));
    assert.equal(failed.status, 502);
});
