import { test } from 'node:test';
import assert from 'node:assert/strict';
import { forwardRecognition, generateSocialCopy, regenerateCaption, reviewCaption } from './recognition.server.ts';
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

test('generates and validates publishing copy through the existing server credential', async () => {
    const previous = process.env.SERVER_ACCESS_TOKEN;
    process.env.SERVER_ACCESS_TOKEN = 'studio-token';
    const expected = {
        xiaohongshu: { title: '小红书', body: '正文', hashtags: ['生活英语'] },
        douyin: { title: '抖音', body: '正文', hashtags: ['跟读'] },
        channels: { title: '视频号', body: '正文', hashtags: ['每日英语'] },
    };
    try {
        const result = await generateSocialCopy({ caption: 'A room.', captionChinese: '一个房间。', words: [{ english: 'room', chinese: '房间' }], highlightedWords: ['room'] }, undefined, async (input, init) => {
            assert.equal(input, 'http://127.0.0.1:8787/v1/social-copy');
            assert.equal(new Headers(init?.headers).get('authorization'), 'Bearer studio-token');
            assert.deepEqual(JSON.parse(String(init?.body)).highlightedWords, ['room']);
            return Response.json(expected);
        });
        assert.deepEqual(result, expected);
    } finally {
        if (previous === undefined) delete process.env.SERVER_ACCESS_TOKEN;
        else process.env.SERVER_ACCESS_TOKEN = previous;
    }
});

test('sends the original image and draft through the studio-only caption review endpoint', async () => {
    const previous = process.env.SERVER_ACCESS_TOKEN;
    process.env.SERVER_ACCESS_TOKEN = 'studio-token';
    const expected = { caption: 'A room has a window.', captionChinese: '房间里有一扇窗。' };
    try {
        const result = await reviewCaption(new Uint8Array([1, 2, 3]), { caption: 'A room.', captionChinese: '一个房间。', words: [{ english: 'room', chinese: '房间' }] }, undefined, async (input, init) => {
            assert.equal(input, 'http://127.0.0.1:8787/v1/studio/caption-review');
            assert.equal(new Headers(init?.headers).get('authorization'), 'Bearer studio-token');
            const form = init?.body as FormData;
            assert.equal(form.get('caption'), 'A room.');
            assert.equal((form.get('image') as Blob).type, 'image/jpeg');
            return Response.json(expected);
        });
        assert.deepEqual(result, expected);
    } finally {
        if (previous === undefined) delete process.env.SERVER_ACCESS_TOKEN;
        else process.env.SERVER_ACCESS_TOKEN = previous;
    }
});

test('regenerates captions from the current reviewed vocabulary without re-recognizing words', async () => {
    const previous = process.env.SERVER_ACCESS_TOKEN;
    process.env.SERVER_ACCESS_TOKEN = 'studio-token';
    const expected = { caption: 'A mug is beside a book.', captionChinese: '杯子放在书旁边。' };
    try {
        const result = await regenerateCaption(new Uint8Array([1, 2, 3]), {
            words: [{ english: 'mug', chinese: '杯子', kind: 'object' }, { english: 'book', chinese: '书', kind: 'object' }],
            context: '桌面',
        }, undefined, async (input, init) => {
            assert.equal(input, 'http://127.0.0.1:8787/v1/studio/caption-regenerate');
            const form = init?.body as FormData;
            assert.deepEqual(JSON.parse(String(form.get('words'))).map((word: { english: string }) => word.english), ['mug', 'book']);
            assert.equal(form.get('context'), '桌面');
            return Response.json(expected);
        });
        assert.deepEqual(result, expected);
    } finally {
        if (previous === undefined) delete process.env.SERVER_ACCESS_TOKEN;
        else process.env.SERVER_ACCESS_TOKEN = previous;
    }
});
