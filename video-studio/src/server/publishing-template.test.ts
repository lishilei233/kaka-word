import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { emptyProject } from '../lib/project';

test('social-copy returns fixed text without network calls and persists the shared scene', async t => {
    const root = await mkdtemp(join(tmpdir(), 'publishing-template-'));
    const previous = process.env.STUDIO_DATA_DIR;
    process.env.STUDIO_DATA_DIR = root;
    const { handleStudioRequest } = await import('./api.server');
    const originalFetch = globalThis.fetch;
    t.after(async () => { globalThis.fetch = originalFetch; if (previous === undefined) delete process.env.STUDIO_DATA_DIR; else process.env.STUDIO_DATA_DIR = previous; await rm(root, { recursive: true, force: true }); });
    globalThis.fetch = async () => { throw new Error('Publishing must not call AI'); };
    const request = (path: string, body?: unknown) => handleStudioRequest(new Request(`http://127.0.0.1/studio-api/${path}`, body === undefined ? {} : { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }));
    const p = { ...emptyProject, publishingScene: '书架一角', words: [{ id: '1', english: 'book', chinese: '书', ipa: '', needsLocation: true }], caption: 'A book.', captionChinese: '一本书。' };
    const response = await request('social-copy', p);
    assert.equal(response.status, 200);
    const copy = await response.json();
    assert.deepEqual(copy.xiaohongshu, copy.douyin);
    assert.deepEqual(copy.douyin, copy.channels);
    assert.equal(copy.xiaohongshu.title, '看照片学单词｜书架一角');
    assert.equal((await request('social-copy', { ...p, publishingScene: '' })).status, 400);
    const record = await (await request('projects', {})).json();
    const saved = await request(`projects/${record.id}`, { revision: record.revision, content: { ...record, project: p } });
    assert.equal(saved.status, 200);
    assert.equal((await (await request(`projects/${record.id}`)).json()).project.publishingScene, '书架一角');
});
