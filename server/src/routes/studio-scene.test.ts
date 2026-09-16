import test from 'node:test';
import assert from 'node:assert/strict';
import { Hono } from 'hono';
import type { AppEnv } from '../app.js';
import { registerStudioSceneRoute } from './studio-scene.js';
import { MockVisionProvider } from '../core/image-analysis/providers/mock.js';
import { studioSceneSchema, studioScenePrompt, type StudioSceneInput } from '../core/image-analysis/studio-scene.js';

const variant = { caption: 'The shell is broken.', captionChinese: '蛋壳破了。' };
const fixture = { theme: '碎鸡蛋', words: [
    { id: 'egg', kind: 'object', english: 'egg', chinese: '鸡蛋', ipa: '/eɡ/', box: { x: .1, y: .1, width: .2, height: .2 } },
    { id: 'broken', kind: 'state', english: 'broken', chinese: '破碎的', ipa: '/ˈbroʊkən/' },
], captionVariants: { serious: variant, funny: variant, literary: variant }, interaction: { english: 'Who made this mess?', chinese: '谁把这里弄乱了？' } };
const token = 'test-studio-token-at-least-32-characters';
function form() {
    const data = new FormData();
    data.set('image', new Blob([new Uint8Array([255,216,255,192,0,11,8,0,20,0,30,1,1,17,0])], { type: 'image/jpeg' }), 'photo.jpg');
    data.set('context', '鸡蛋刚掉到地上'); data.set('maxWords', '8'); return data;
}
test('studio scene endpoint is dedicated, authenticated and forwards image and background', async () => {
    const app = new Hono<AppEnv>(); const provider = new MockVisionProvider(); let received: StudioSceneInput | undefined;
    Object.assign(provider, { analyzeStudioScene: async (input: StudioSceneInput) => { received = input; return fixture; } });
    registerStudioSceneRoute(app, { provider, videoStudioAccessToken: token });
    assert.equal((await app.request('/v1/studio/scene', { method: 'POST', body: form() })).status, 401);
    assert.equal(received, undefined);
    const response = await app.request('/v1/studio/scene', { method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: form() });
    assert.equal(response.status, 200);
    const input = received as StudioSceneInput | undefined;
    assert.equal(input?.context, '鸡蛋刚掉到地上');
    assert.ok(input!.image.length > 0);
    const result = await response.json();
    assert.equal(result.words[1].box, undefined);
    const invalid = form(); invalid.set('maxWords', '99');
    assert.equal((await app.request('/v1/studio/scene', { method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: invalid })).status, 400);
});
test('scene schema rejects invented geometry and duplicate IDs and prompt requires visual evidence', () => {
    assert.equal(studioSceneSchema.safeParse(fixture).success, true);
    assert.equal(studioSceneSchema.safeParse({ ...fixture, words: [{ ...fixture.words[0], box: undefined }] }).success, false);
    assert.equal(studioSceneSchema.safeParse({ ...fixture, words: [fixture.words[0], fixture.words[0]] }).success, false);
    assert.match(studioScenePrompt({ context: '', maxWords: 8 }), /Static scenes are valid/);
    assert.match(studioScenePrompt({ context: '', maxWords: 8 }), /must not be invented/);
});
