import test from 'node:test';
import assert from 'node:assert/strict';
import { Autosave } from './autosave';
import { emptyProject } from './project';
import type { ProjectContent, ProjectRecord } from './project-record';
const record: ProjectRecord = { id: 'a', createdAt: '', updatedAt: '', revision: 0, project: emptyProject, editor: { source: '', pendingLivePhotoVideo: '' } };
const content = (title: string): ProjectContent => ({ project: { ...emptyProject, title }, editor: record.editor });
const tick = () => new Promise(resolve => setImmediate(resolve));
function clock() {
    let now = 0, id = 0;
    const timers = new Map<number, { at: number; fn: () => void }>();
    return {
        set(fn: () => void, delay: number) { const key = ++id; timers.set(key, { at: now + delay, fn }); return key; },
        clear(key: unknown) { timers.delete(key as number); },
        async advance(ms: number) { const until = now + ms; while (true) { const next = [...timers].filter(([, t]) => t.at <= until).sort((a, b) => a[1].at - b[1].at)[0]; if (!next) break; now = next[1].at; timers.delete(next[0]); next[1].fn(); await tick(); } now = until; },
    };
}
test('no save on load; debounce after editing and max wait during continuous edits', async () => {
    const time = clock(); const saved: string[] = [];
    const saver = new Autosave(record, async (revision, value) => { saved.push(value.project.title); return { ...record, ...value, revision: revision + 1 }; }, () => {}, time);
    saver.change({ project: record.project, editor: record.editor });
    await time.advance(10000); assert.equal(saved.length, 0);
    saver.change(content('A')); await time.advance(900); assert.equal(saved.length, 0);
    saver.change(content('B')); await time.advance(999); assert.equal(saved.length, 0);
    await time.advance(1); assert.deepEqual(saved, ['B']);
    for (let i = 0; i < 20; i++) { saver.change(content(String(i))); await time.advance(500); }
    assert.equal(saved.length, 2); assert.equal(saved[1], '19');
});
test('in-flight edit remains dirty and drains serially before leaving', async () => {
    const writes: { revision: number; value: ProjectContent; resolve: (r: ProjectRecord) => void }[] = [];
    const saver = new Autosave(record, (revision, value) => new Promise(resolve => writes.push({ revision, value, resolve })), () => {});
    saver.change(content('A')); const leaving = saver.flush();
    saver.change(content('B')); assert.equal(writes.length, 1);
    writes[0].resolve({ ...record, revision: 1 }); await tick();
    assert.equal(saver.dirty, true); assert.equal(saver.status, 'saving');
    assert.equal(writes.length, 2); assert.equal(writes[1].revision, 1); assert.equal(writes[1].value.project.title, 'B');
    writes[1].resolve({ ...record, revision: 2 }); assert.equal(await leaving, true);
    assert.equal(saver.dirty, false); saver.dispose();
});
test('failure blocks leaving, retry saves latest edit, conflict never retries overwriting', async () => {
    let fail = true, calls = 0;
    const saver = new Autosave(record, async (revision, value) => { calls++; if (fail) throw new Error('离线'); return { ...record, ...value, revision: revision + 1 }; }, () => {});
    saver.change(content('A')); assert.equal(await saver.flush(), false); assert.equal(saver.status, 'error');
    saver.change(content('B')); fail = false; assert.equal(await saver.flush(), true); assert.equal(calls, 2);
    const conflict = new Autosave(record, async () => { throw Object.assign(new Error('冲突'), { status: 409 }); }, () => {});
    conflict.change(content('A')); assert.equal(await conflict.flush(), false);
    conflict.change(content('B')); assert.equal(await conflict.flush(), false); assert.equal(conflict.status, 'conflict');
    assert.equal(conflict.content.project.title, 'B'); saver.dispose(); conflict.dispose();
});
test('dispose cancels scheduled writes', async () => {
    const time = clock(); let calls = 0;
    const saver = new Autosave(record, async () => { calls++; return record; }, () => {}, time);
    saver.change(content('A')); saver.dispose(); await time.advance(10000); assert.equal(calls, 0);
});

test('development effect cleanup and reactivation keep editing and saving available', async () => {
    let calls = 0;
    const saver = new Autosave(record, async (revision, value) => { calls++; return { ...record, ...value, revision: revision + 1 }; }, () => {});
    saver.dispose(); saver.resume(); saver.change(content('重新挂载后编辑'));
    assert.equal(await saver.flush(), true); assert.equal(calls, 1); assert.equal(saver.dirty, false);
    saver.dispose();
});
