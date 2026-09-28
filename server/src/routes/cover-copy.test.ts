import test from 'node:test';
import assert from 'node:assert/strict';
import { Hono } from 'hono';
import type { AppEnv } from '../app.js';
import { registerCoverCopyRoute } from './cover-copy.js';
import { MockVisionProvider } from '../core/image-analysis/providers/mock.js';
import { coverCopyPrompt, coverCopySchema, type CoverCopy } from '../core/image-analysis/cover-copy.js';
import { QwenVisionProvider } from '../core/image-analysis/providers/qwen.js';

const input = { sceneTheme: '酒店抽屉', caption: 'A mug is in the drawer.', captionChinese: '抽屉里有杯子。', words: [{ english: 'mug', chinese: '杯子' }] };
const token = 'test-studio-token-at-least-32-characters';
function app(provider = new MockVisionProvider()) {
    const app = new Hono<AppEnv>();
    registerCoverCopyRoute(app, { provider, videoStudioAccessToken: token });
    return app;
}
function request(value: unknown = input, authorization: string = token, signal?: AbortSignal) {
    return new Request('http://localhost/v1/studio/cover-copy', { method: 'POST', headers: { Authorization: `Bearer ${authorization}`, 'Content-Type': 'application/json' }, body: JSON.stringify(value), signal });
}
test('cover suggestions require studio authentication and valid description/vocabulary', async () => {
    assert.equal((await app().fetch(request(input, 'incorrect'))).status, 401);
    for (const invalid of [{ ...input, words: [] }, { ...input, caption: '' }, { ...input, words: [{ english: '', chinese: '' }] }]) assert.equal((await app().fetch(request(invalid))).status, 400);
});
test('cover suggestions return three distinct candidates for each audience', async () => {
    const response = await app().fetch(request());
    assert.equal(response.status, 200);
    const copy = coverCopySchema.parse(await response.json());
    for (const titles of Object.values(copy)) { assert.equal(titles.length, 3); assert.equal(new Set(titles).size, 3); }
    assert.match(coverCopyPrompt(input), /untrusted source content/);
    assert.match(coverCopyPrompt(input), /exam relevance/);
});
test('invalid model output and provider failure do not escape the route', async () => {
    const provider = new MockVisionProvider();
    provider.generateCoverCopy = async () => ({ adult: ['bad'] } as unknown as CoverCopy);
    assert.equal((await app(provider).fetch(request())).status, 502);
    provider.generateCoverCopy = async () => { throw new Error('provider failed'); };
    const response = await app(provider).fetch(request());
    assert.equal(response.status, 502);
    assert.match((await response.json()).message, /原内容未改变/);
});
test('cancelled request reaches provider and cannot return stale success', async () => {
    const provider = new MockVisionProvider();
    const original = provider.generateCoverCopy.bind(provider);
    provider.generateCoverCopy = async args => { assert.ok(args.signal?.aborted); return original(args); };
    const controller = new AbortController(); controller.abort(new DOMException('Timed out', 'TimeoutError'));
    assert.equal((await app(provider).fetch(request(input, token, controller.signal))).status, 502);
});
test('Qwen cover generation uses configured provider and validates its JSON response', async () => {
    const original = globalThis.fetch;
    const expected = await new MockVisionProvider().generateCoverCopy(input);
    try {
        globalThis.fetch = async (_url, init) => {
            const body = JSON.parse(String(init?.body));
            assert.equal(body.model, 'test-model');
            assert.equal(body.response_format.type, 'json_object');
            assert.match(body.messages[0].content, /hotel|酒店抽屉/);
            return Response.json({ choices: [{ message: { content: JSON.stringify(expected) } }] });
        };
        const provider = new QwenVisionProvider({ apiKey: 'test-key', apiHost: 'https://example.com', model: 'test-model' });
        assert.deepEqual(await provider.generateCoverCopy(input), expected);
        globalThis.fetch = async () => Response.json({ choices: [{ message: { content: '{"adult":[]}' } }] });
        await assert.rejects(() => provider.generateCoverCopy(input));
    } finally { globalThis.fetch = original; }
});
