import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateCoverCopy } from './recognition.server';
const input = { sceneTheme: '酒店', caption: 'A mug.', captionChinese: '一个杯子。', words: [{ english: 'mug', chinese: '杯子' }] };
const copy = { adult: ['一？', '二？', '三？'], family: ['四？', '五？', '六？'], student: ['七？', '八？', '九？'] };
test('cover copy forwards studio credentials and validates all three audiences', async () => {
    const previous = process.env.SERVER_ACCESS_TOKEN; process.env.SERVER_ACCESS_TOKEN = 'test-studio-token';
    try {
        const result = await generateCoverCopy(input, undefined, async (url, init) => {
            assert.match(String(url), /\/v1\/studio\/cover-copy$/);
            assert.equal(new Headers(init?.headers).get('authorization'), 'Bearer test-studio-token');
            assert.deepEqual(JSON.parse(String(init?.body)), input);
            assert.equal(init?.redirect, 'error');
            assert.ok(init?.signal);
            return Response.json(copy);
        });
        assert.deepEqual(result, copy);
    } finally { if (previous === undefined) delete process.env.SERVER_ACCESS_TOKEN; else process.env.SERVER_ACCESS_TOKEN = previous; }
});
test('cover copy rejects invalid JSON shapes, auth errors and timeout', async () => {
    await assert.rejects(() => generateCoverCopy(input, undefined, async () => Response.json({ adult: ['bad'] })), /格式无效/);
    await assert.rejects(() => generateCoverCopy(input, undefined, async () => Response.json({ message: '凭证失效' }, { status: 401 })), /凭证失效/);
    const controller = new AbortController(); controller.abort(new DOMException('Timed out', 'TimeoutError'));
    await assert.rejects(() => generateCoverCopy(input, controller.signal, async (_url, init) => { init?.signal?.throwIfAborted(); return Response.json(copy); }), /中断或超时/);
});
