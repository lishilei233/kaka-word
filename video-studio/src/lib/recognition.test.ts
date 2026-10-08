import { test } from 'node:test';
import assert from 'node:assert/strict';
import { constrainRecognitionBox, recognitionAnimation, recognitionBox, recognitionCorners, recognitionFocusBox, resizeRecognitionBox } from './recognition';
import { emptyProject, projectSchema, timeline, type Project, type Word } from './project';
const word: Word = { id: 'cup', english: 'a very long English object phrase', chinese: '杯子', ipa: '', box: { x: .7, y: .5, width: .2, height: .3 } };
test('recognition corners last exactly six frames before the eight-frame label growth', () => {
    for (const from of [15, 68]) {
        assert.equal(recognitionAnimation(from - 1, from).cornersVisible, false);
        for (const offset of [0, 3, 5]) {
            assert.equal(recognitionAnimation(from + offset, from).cornersVisible, true);
            assert.equal(recognitionAnimation(from + offset, from).progress, 0);
        }
        assert.equal(recognitionAnimation(from + 6, from).cornersVisible, false);
        assert.equal(recognitionAnimation(from + 6, from).progress, 0);
        assert.ok(recognitionAnimation(from + 10, from).progress > 0);
        assert.equal(recognitionAnimation(from + 14, from).progress, 1);
    }
});
test('moving and each resize corner respect photo boundaries and minimum size', () => {
    assert.deepEqual(constrainRecognitionBox({ x: 1, y: -2, width: 0, height: 2 }), { x: .98, y: 0, width: .02, height: 1 });
    const box = recognitionBox(word)!;
    for (const corner of ['nw', 'ne', 'sw', 'se']) {
        for (const delta of [-5, 5]) {
            const next = resizeRecognitionBox(box, corner, delta, delta);
            assert.ok(next.x >= 0 && next.y >= 0);
            assert.ok(next.width >= .02 - 1e-9 && next.height >= .02 - 1e-9);
            assert.ok(next.x + next.width <= 1 + 1e-9 && next.y + next.height <= 1 + 1e-9);
        }
    }
    assert.equal((recognitionCorners(4, 4).match(/M /g) ?? []).length, 4);
    assert.equal((recognitionCorners(4, 4).match(/Q /g) ?? []).length, 4);
});
test('recognition override survives v4 drafts without changing original boxes, speech or timelines', () => {
    const audio = '/studio-api/assets/00000000-0000-4000-8000-000000000001.wav';
    for (const videoTemplate of ['direct', 'camera'] as const) {
        const before = { ...emptyProject, videoTemplate, words: [{ ...word, audio, audioSeconds: 1 }] };
        const saved = projectSchema.parse({ ...before, words: [{ ...before.words[0], recognitionBoxOverride: { x: .1, y: .1, width: .5, height: .5 } }] });
        const restored = projectSchema.parse(JSON.parse(JSON.stringify(saved)));
        assert.equal(restored.version, 5);
        assert.deepEqual(restored.words[0].box, word.box);
        assert.equal(restored.words[0].audio, audio);
        const times = (p: Project) => { const t = timeline(p); return { ...t, words: t.words.map(({ word: _word, ...segment }) => segment) }; };
        assert.deepEqual(times(restored), times(before));
    }
});
test('legacy ranges remain usable and unlocated and scene words do not render boxes', () => {
    assert.deepEqual(recognitionBox(word), word.box);
    assert.equal(recognitionBox({ ...word, needsLocation: true }), undefined);
    assert.equal(recognitionBox({ ...word, kind: 'verb' }), undefined);
    assert.equal(recognitionBox({ ...word, box: undefined }), undefined);
    assert.equal(projectSchema.safeParse({ ...emptyProject, words: [{ ...word, recognitionBoxOverride: { x: .99, y: .9, width: .2, height: .2 } }] }).success, false);
});

test('focus corners converge onto the saved range without crossing photo edges', () => {
    for (const box of [{ x: .4, y: .4, width: .2, height: .2 }, { x: 0, y: .98, width: .02, height: .02 }, { x: .98, y: 0, width: .02, height: .02 }]) {
        const first = recognitionFocusBox(box, recognitionAnimation(0, 0).focusProgress);
        const middle = recognitionFocusBox(box, recognitionAnimation(3, 0).focusProgress);
        const final = recognitionFocusBox(box, recognitionAnimation(5, 0).focusProgress);
        assert.ok(first.width >= middle.width && middle.width >= final.width - 1e-9);
        for (const rect of [first, middle, final]) {
            assert.ok(rect.x >= 0 && rect.y >= 0);
            assert.ok(rect.x + rect.width <= 1 && rect.y + rect.height <= 1);
        }
        for (const key of ['x', 'y', 'width', 'height'] as const) assert.ok(Math.abs(final[key] - box[key]) < 1e-9);
    }
});

test('adjectives focus their associated noun range including manual edits', () => {
    const adjective: Word = { id: 'leafy', english: 'leafy', chinese: '枝叶茂密的', ipa: '', kind: 'adjective', relatedObjectID: word.id,
        box: { x: 0, y: 0, width: .1, height: .1 } };
    const edited = { ...word, recognitionBoxOverride: { x: .2, y: .3, width: .4, height: .5 } };
    assert.deepEqual(recognitionBox(adjective, [word, adjective]), word.box);
    assert.deepEqual(recognitionBox(adjective, [edited, adjective]), edited.recognitionBoxOverride);
    assert.equal(recognitionBox(adjective, [adjective]), undefined);
    assert.equal(recognitionBox(adjective, [{ ...word, needsLocation: true }]), undefined);
    assert.equal(recognitionBox(adjective, [{ ...word, box: undefined }]), undefined);
    assert.equal(recognitionBox(adjective, [{ ...word, kind: 'adjective' }]), undefined);
    assert.equal(recognitionBox({ ...adjective, kind: 'verb' }, [word]), undefined);
});

test('rounded brackets include stroke inset for tiny and wide photos', () => {
    for (const [width, height, scale] of [[4, 4, 1], [540, 100, 1], [10, 500, 1], [32, 42, 320 / 540]]) {
        const path = recognitionCorners(width, height, scale);
        const inset = 2 * Math.min(scale, Math.min(width, height) / 16);
        const points = [...path.matchAll(/[MLQ] ([\d.e+-]+) ([\d.e+-]+)/g)];
        assert.equal((path.match(/M /g) ?? []).length, 4);
        assert.equal((path.match(/Q /g) ?? []).length, 4);
        for (const [, x, y] of points) {
            assert.ok(+x >= inset - 1e-9 && +x <= width - inset + 1e-9);
            assert.ok(+y >= inset - 1e-9 && +y <= height - inset + 1e-9);
        }
    }
});
