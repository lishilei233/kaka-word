import test from 'node:test';
import assert from 'node:assert/strict';
import { Hono } from 'hono';
import type { AppEnv } from '../app.js';
import { registerStudioSceneRoute } from './studio-scene.js';
import { MockVisionProvider } from '../core/image-analysis/providers/mock.js';
import { studioSceneSchema, studioScenePrompt, type StudioSceneInput } from '../core/image-analysis/studio-scene.js';
import { captionReviewPrompt, learningObjectPrompt } from '../core/image-analysis/prompts.js';

const variant = { caption: 'The shell is broken.', captionChinese: '蛋壳破了。' };
const fixture = { theme: '碎鸡蛋', words: [
    { id: 'broken', kind: 'state', english: 'broken', chinese: '破碎的', ipa: '/ˈbroʊkən/' },
], ...variant, interaction: { english: 'Who made this mess?', chinese: '谁把这里弄乱了？' } };
const recognized = { imageWidth: 30, imageHeight: 20, objects: [
    { id: 'egg', english: 'egg', chinese: '鸡蛋', ipa: '/eɡ/', confidence: .98, box: { x: .1, y: .1, width: .2, height: .2 }, anchor: { x: .2, y: .2 }, example: 'This is an egg.', exampleChinese: '这是一个鸡蛋。', confirmationStatus: 'confirmed' as const },
], caption: 'An egg is on the floor.', captionChinese: '一个鸡蛋在地板上。', captionStyle: 'serious' as const };
const token = 'test-studio-token-at-least-32-characters';
function form() {
    const data = new FormData();
    data.set('image', new Blob([new Uint8Array([255,216,255,192,0,11,8,0,20,0,30,1,1,17,0])], { type: 'image/jpeg' }), 'photo.jpg');
    data.set('context', '鸡蛋刚掉到地上'); data.set('maxObjects', '8'); return data;
}
function reviewForm() {
    const data = form();
    data.set('caption', 'The colorful drinks are ready, so customers wait for their paper bags.');
    data.set('captionChinese', '五颜六色的饮料准备好了，所以顾客们在等待他们的纸袋。');
    data.set('words', JSON.stringify([
        { english: 'drinks', chinese: '饮料', kind: 'object' },
        { english: 'paper bags', chinese: '纸袋', kind: 'object' },
    ]));
    return data;
}
function regenerateForm() {
    const data = form();
    data.set('words', JSON.stringify([
        { english: 'drink', chinese: '饮料', kind: 'object' },
        { english: 'paper bag', chinese: '纸袋', kind: 'object' },
    ]));
    return data;
}
test('studio scene endpoint is dedicated, authenticated and forwards image and background', async () => {
    const app = new Hono<AppEnv>(); const provider = new MockVisionProvider(); let received: StudioSceneInput | undefined;
    Object.assign(provider, {
        analyze: async () => recognized,
        analyzeStudioScene: async (input: StudioSceneInput) => { received = input; return fixture; },
        reviewCaption: async () => variant,
    });
    registerStudioSceneRoute(app, { provider, videoStudioAccessToken: token });
    assert.equal((await app.request('/v1/studio/scene', { method: 'POST', body: form() })).status, 401);
    assert.equal(received, undefined);
    const response = await app.request('/v1/studio/scene', { method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: form() });
    assert.equal(response.status, 200);
    const input = received as StudioSceneInput | undefined;
    assert.equal(input?.context, '鸡蛋刚掉到地上');
    assert.deepEqual(input?.objects, [{ english: 'egg', chinese: '鸡蛋' }]);
    assert.ok(input!.image.length > 0);
    const result = await response.json();
    assert.deepEqual(result.words.map((word: { english: string }) => word.english), ['egg', 'broken']);
    assert.equal(result.words[1].box, undefined);
    const invalid = form(); invalid.set('maxObjects', '99');
    assert.equal((await app.request('/v1/studio/scene', { method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: invalid })).status, 400);
});
test('scene schema rejects invented geometry and duplicate IDs and prompt requires visual evidence', () => {
    assert.equal(studioSceneSchema.safeParse(fixture).success, true);
    assert.equal(studioSceneSchema.safeParse({ ...fixture, words: [{ id: 'egg', kind: 'object', english: 'egg', chinese: '鸡蛋', ipa: '', box: undefined }] }).success, false);
    assert.equal(studioSceneSchema.safeParse({ ...fixture, words: [fixture.words[0], fixture.words[0]] }).success, false);
    assert.match(studioScenePrompt({ context: '', objects: [{ english: 'egg', chinese: '鸡蛋' }] }), /authoritative object-recognition pipeline/);
    assert.match(studioScenePrompt({ context: '', objects: [] }), /Static scenes are valid/);
    assert.match(studioScenePrompt({ context: '', objects: [] }), /must not be invented/);
    assert.match(studioScenePrompt({ context: '', objects: [] }), /Never say an inanimate object “waits”/);
    assert.match(studioScenePrompt({ context: '', objects: [] }), /Drinks and paper bags sit on the counter/);
    assert.match(studioScenePrompt({ context: '', objects: [] }), /Return one factual English description and one natural Chinese description/);
    assert.match(studioScenePrompt({ context: '', objects: [] }), /no more than 40 words/);
    assert.match(studioScenePrompt({ context: '', objects: [{ english: 'window', chinese: '窗户' }] }), /Use as many supplied object words as fit naturally/);
});

test('caption review requires image-grounded facts and natural bilingual output', () => {
    const scenePrompt = captionReviewPrompt({
        caption: 'A room is ready for practice.', captionChinese: '房间已经准备好练习。',
        words: [
            { english: 'practice', chinese: '练习', kind: 'action' },
            { english: 'empty', chinese: '空的', kind: 'state' },
            { english: 'room', chinese: '房间', kind: 'object' },
        ],
    });
    assert.match(scenePrompt, /practice/);
    assert.match(scenePrompt, /empty/);
    assert.match(scenePrompt, /customer\/employee identity needs clothing/);
    assert.match(scenePrompt, /ownership needs direct holding or use/);
    assert.match(scenePrompt, /same supported meaning/);
    assert.match(scenePrompt, /avoid agentive or inferred words such as wait/);
    assert.match(scenePrompt, /do not change cup to drink, scanner to QR-code sign, or screen to products/);

    const objectPrompt = captionReviewPrompt({
        caption: 'A room is ready.', captionChinese: '房间准备好了。',
        words: [{ english: 'room', chinese: '房间', kind: 'object' }],
    });
    assert.match(objectPrompt, /return one corrected final description/);
    assert.match(objectPrompt, /visible vocabulary is authoritative and locked/);
    assert.match(learningObjectPrompt(8, 'serious'), /no more than 24 words/);
    assert.match(learningObjectPrompt(8, 'serious'), /Use as many clearly visible supplied object words as naturally fit/);
});

test('caption review replaces unsupported claims and fails closed', async () => {
    const app = new Hono<AppEnv>();
    const provider = new MockVisionProvider();
    Object.assign(provider, {
        reviewCaption: async () => ({
            caption: 'Colorful drinks and paper bags are on the counter.',
            captionChinese: '柜台上放着彩色饮料和纸袋。',
        }),
    });
    registerStudioSceneRoute(app, { provider, videoStudioAccessToken: token });
    const reviewed = await app.request('/v1/studio/caption-review', {
        method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: reviewForm(),
    });
    assert.equal(reviewed.status, 200);
    assert.deepEqual(await reviewed.json(), {
        caption: 'Colorful drinks and paper bags are on the counter.',
        captionChinese: '柜台上放着彩色饮料和纸袋。',
    });

    Object.assign(provider, { reviewCaption: async () => { throw new Error('timeout'); } });
    const failed = await app.request('/v1/studio/caption-review', {
        method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: reviewForm(),
    });
    assert.equal(failed.status, 502);
    assert.deepEqual(await failed.json(), { message: '照片描述审校失败，原内容未改变，请重试' });
});

test('scene analysis never returns its unreviewed draft when review fails', async () => {
    const app = new Hono<AppEnv>();
    const provider = new MockVisionProvider();
    Object.assign(provider, {
        analyze: async () => recognized,
        analyzeStudioScene: async () => fixture,
        reviewCaption: async () => { throw new Error('invalid JSON'); },
    });
    registerStudioSceneRoute(app, { provider, videoStudioAccessToken: token });
    const response = await app.request('/v1/studio/scene', {
        method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: form(),
    });
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), { message: '场景分析失败，请重试或切换物体识别' });
});

test('caption regeneration uses the submitted final vocabulary for both generation and review', async () => {
    const app = new Hono<AppEnv>();
    const provider = new MockVisionProvider();
    const received: string[][] = [];
    Object.assign(provider, {
        generateCaption: async (input: { words: { english: string }[] }) => {
            received.push(input.words.map(word => word.english));
            return { caption: 'Drinks and paper bags are ready.', captionChinese: '饮料和纸袋准备好了。' };
        },
        reviewCaption: async (input: { words: { english: string }[] }) => {
            received.push(input.words.map(word => word.english));
            return { caption: 'Drinks and paper bags are on the counter.', captionChinese: '柜台上放着饮料和纸袋。' };
        },
    });
    registerStudioSceneRoute(app, { provider, videoStudioAccessToken: token });
    const response = await app.request('/v1/studio/caption-regenerate', {
        method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: regenerateForm(),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(received, [['drink', 'paper bag'], ['drink', 'paper bag']]);
    assert.deepEqual(await response.json(), {
        caption: 'Drinks and paper bags are on the counter.', captionChinese: '柜台上放着饮料和纸袋。',
    });
});
