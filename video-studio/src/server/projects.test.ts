import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ProjectStore } from './projects.server';
import { emptyProject } from '../lib/project';

async function fixture(t: { after: (fn: () => Promise<void>) => void }) {
    const root = await mkdtemp(join(tmpdir(), 'studio-projects-'));
    t.after(() => rm(root, { recursive: true, force: true }));
    return { root, store: new ProjectStore(root) };
}
test('independent projects, copies, rename, restart and delete preserve shared assets', async t => {
    const { root, store } = await fixture(t);
    const first = await store.create();
    const second = await store.create();
    const source = '/studio-api/assets/abcd.mp4';
    const content = { project: { ...first.project, title: '第一部' }, editor: { source, pendingLivePhotoVideo: '' } };
    await store.update(first.id, first.revision, content);
    assert.equal((await store.get(second.id)).project.title, '未命名视频');
    const copy = await store.copy(first.id);
    assert.equal(copy.project.title, '第一部 副本');
    assert.equal(copy.editor.source, source);
    await store.update(copy.id, copy.revision, { ...copy, project: { ...copy.project, title: '第二版内容' } });
    assert.equal((await store.get(first.id)).project.title, '第一部');
    await store.remove(first.id, 1);
    assert.equal((await new ProjectStore(root).get(copy.id)).editor.source, source);
    assert.equal((await store.list()).length, 2);
    await assert.rejects(store.get(first.id), { status: 404 });
});
test('concurrent writes accept one revision and reject stale writes/deletion', async t => {
    const { store } = await fixture(t);
    const record = await store.create();
    const results = await Promise.allSettled([store.update(record.id, 0, record), store.update(record.id, 0, record)]);
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal((results.find(r => r.status === 'rejected') as PromiseRejectedResult).reason.status, 409);
    await assert.rejects(store.remove(record.id, 0), { status: 409 });
    assert.equal((await store.get(record.id)).revision, 1);
});
test('legacy migration is idempotent and retains original even after deleting imported work', async t => {
    const { root, store } = await fixture(t);
    const text = JSON.stringify({ ...emptyProject, title: '原草稿' });
    await writeFile(join(root, 'project.json'), text);
    const [record] = await store.list();
    assert.equal(record.title, '原草稿');
    assert.equal((await new ProjectStore(root).list()).length, 1);
    assert.equal(await readFile(join(root, 'project.json'), 'utf8'), text);
    await store.remove(record.id, 0);
    assert.equal((await new ProjectStore(root).list()).length, 0);
});
test('corrupt migration and invalid IDs never silently create blank work', async t => {
    const { root, store } = await fixture(t);
    await writeFile(join(root, 'project.json'), '{broken');
    await assert.rejects(store.list(), /迁移失败/);
    await assert.rejects(store.create(), /迁移失败/);
    await writeFile(join(root, 'project.json'), JSON.stringify(emptyProject));
    assert.equal((await store.list()).length, 1);
    await assert.rejects(store.get('../project'), { status: 400 });
});
