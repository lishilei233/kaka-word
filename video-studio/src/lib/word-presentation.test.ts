import test from 'node:test';
import assert from 'node:assert/strict';
import { emptyProject, recognitionWords, annotatedWords, bottomVerbs, readingWords, projectSchema, withReviewedCaption, timeline, readingGroups, activeWord, AUDIO_LEAD_FRAMES, AUDIO_TAIL_FRAMES, FPS } from './project';
import { renderToStaticMarkup } from 'react-dom/server';
import { createElement } from 'react';
import { SceneCards } from '../video/SceneCards';
import { filmLayout } from './film-layout';

const p = { ...emptyProject, caption: 'She ran near a cup.', captionChinese: '她跑过一个杯子。', words: [
    { id: 'cup', kind: 'noun' as const, english: 'cup', chinese: '杯子', ipa: '', box: { x: .2, y: .2, width: .3, height: .3 }, anchor: { x: .25, y: .3 } },
    { id: 'empty', kind: 'adjective' as const, english: 'empty', chinese: '空的', ipa: '', relatedObjectID: 'cup', labelCenterOverride: { x: .8, y: .7 }, targetCenterOverride: { x: .3, y: .3 } },
    { id: 'cold', kind: 'adjective' as const, english: 'cold', chinese: '冷的', ipa: '' },
    { id: 'run', kind: 'verb' as const, english: 'run', chinese: '跑', ipa: '' },
] };

test('project round trip preserves relation, independent edits, evidence and hidden words', () => {
    const reviewed = withReviewedCaption(p, { caption: p.caption, captionChinese: p.captionChinese, verbMatches: [{ english: 'run', captionForm: 'ran' }] });
    const restored = projectSchema.parse(JSON.parse(JSON.stringify(reviewed)));
    assert.equal(restored.words.length, 4);
    assert.deepEqual(annotatedWords(restored.words).map(w => w.id), ['cup', 'empty']);
    assert.deepEqual(annotatedWords(restored.words)[1].targetCenterOverride, { x: .3, y: .3 });
    assert.deepEqual(readingWords(restored.words, restored.caption).map(w => w.id), ['cup', 'empty', 'run']);
    assert.deepEqual(timeline(restored).words.map(w => w.word.id), ['cup', 'empty', 'run']);
    assert.deepEqual(annotatedWords(restored.words.filter(w => w.id !== 'cup')), []);
    assert.deepEqual(bottomVerbs(restored.words, 'She has a running shoe.'), []);
});

test('unverified verbs and unassociated adjectives leave no bottom strip or speech segment', () => {
    assert.deepEqual(bottomVerbs(p.words, p.caption), []);
    assert.deepEqual(timeline(p).words.map(w => w.word.id), ['cup', 'empty']);
    assert.equal(filmLayout(p).sceneHeight, 0);
    assert.equal(renderToStaticMarkup(createElement(SceneCards, { project: p })), '');
});

test('review updates inflection evidence and removed words lose their reading segment', () => {
    const changed = withReviewedCaption(p, { caption: 'She is running near a cup.', captionChinese: '她正跑过一个杯子。', verbMatches: [{ english: 'run', captionForm: 'running' }] });
    assert.deepEqual(bottomVerbs(changed.words, changed.caption).map(w => w.english), ['run']);
    const removed = withReviewedCaption(changed, { caption: 'An empty cup.', captionChinese: '一个空杯子。', verbMatches: [] });
    assert.equal(removed.words.length, p.words.length);
    assert.deepEqual(bottomVerbs(removed.words, removed.caption), []);
});

test('cover annotations render noun and adjective leaders while bottom cards contain verbs only', async () => {
    const { CoverAnnotations } = await import('../video/CoverAnnotations');
    const reviewed = withReviewedCaption(p, { caption: p.caption, captionChinese: p.captionChinese, verbMatches: [{ english: 'run', captionForm: 'ran' }] });
    const annotations = renderToStaticMarkup(createElement(CoverAnnotations, { project: reviewed, photo: { x: 0, y: 0, width: 1080, height: 1440 } }));
    assert.match(annotations, /cup/);
    assert.match(annotations, /empty/);
    assert.doesNotMatch(annotations, /cold/);
    assert.equal((annotations.match(/<path /g) ?? []).length, 4);
    const cards = renderToStaticMarkup(createElement(SceneCards, { project: reviewed }));
    assert.match(cards, /run/);
    assert.doesNotMatch(cards, /empty|cup|cold/);
});


test('default recognition retains full/empty and exact parent IDs after photo sorting', () => {
    const objects = [
        { id: 'full-cup', english: 'cup', chinese: '杯子', ipa: '', box: { x: .7, y: .1, width: .2, height: .3 } },
        { id: 'empty-cup', english: 'cup', chinese: '杯子', ipa: '', box: { x: .1, y: .1, width: .2, height: .3 } },
    ];
    const states = [
        { id: 'full', kind: 'adjective' as const, english: 'full', chinese: '满的', ipa: '', relatedObjectID: 'full-cup' },
        { id: 'empty', kind: 'adjective' as const, english: 'empty', chinese: '空的', ipa: '', relatedObjectID: 'empty-cup' },
    ];
    const words = recognitionWords({ objects, sceneWords: states });
    assert.deepEqual(words.slice(0, 2).map(w => w.id), ['empty-cup', 'full-cup']);
    const annotations = annotatedWords(words);
    assert.deepEqual(annotations.find(w => w.id === 'full')?.box, objects[0].box);
    assert.deepEqual(annotations.find(w => w.id === 'empty')?.box, objects[1].box);
    assert.equal(recognitionWords({ objects }).length, 2);
});

test('version 1 through 4 projects migrate legacy kinds to version 5 without losing edits or speech', () => {
    for (const version of [1, 2, 3, 4]) {
        const reviewed = withReviewedCaption(p, { caption: p.caption, captionChinese: p.captionChinese, verbMatches: [{ english: 'run', captionForm: 'ran' }] });
        const legacy = { ...reviewed, version, words: reviewed.words.map(w => ({ ...w, kind: { noun: 'object', adjective: 'state', verb: 'action' }[w.kind!], audio: '/studio-api/assets/1234.wav', audioSeconds: 1.2 })) };
        if (version === 1) Object.assign(legacy, { words: legacy.words.map(w => ({ ...w, x: w.labelCenterOverride?.x ?? .5, y: w.labelCenterOverride?.y ?? .5, targetX: w.targetCenterOverride?.x ?? .3, targetY: w.targetCenterOverride?.y ?? .3 })) });
        const restored = projectSchema.parse(legacy);
        assert.equal(restored.version, 5);
        assert.deepEqual(restored.words.map(w => w.kind), ['noun', 'adjective', 'adjective', 'verb']);
        assert.equal(restored.words[1].relatedObjectID, 'cup');
        assert.deepEqual(restored.words[1].labelCenterOverride, p.words[1].labelCenterOverride);
        assert.equal(restored.words[3].captionForm, 'ran');
        assert.equal(restored.words[3].audio, '/studio-api/assets/1234.wav');
        assert.deepEqual(JSON.parse(JSON.stringify(projectSchema.parse(JSON.parse(JSON.stringify(restored))))), JSON.parse(JSON.stringify(restored)));
    }
});


test('reading groups follow exact object IDs with multiple adjectives and omit invalid associations', () => {
    const words = [
        { ...p.words[0], id: 'left-cup' }, { ...p.words[0], id: 'right-cup' },
        { ...p.words[1], id: 'full', relatedObjectID: 'right-cup' },
        { ...p.words[1], id: 'empty', relatedObjectID: 'left-cup' },
        { ...p.words[1], id: 'blue', relatedObjectID: 'left-cup' },
        { ...p.words[1], id: 'orphan', relatedObjectID: 'deleted-cup' },
        { ...p.words[3], captionForm: 'ran', captionEvidence: p.caption },
    ];
    assert.deepEqual(readingGroups(words, p.caption).map(group => group.map(w => w.id)), [['left-cup', 'empty', 'blue'], ['right-cup', 'full'], ['run']]);
    assert.deepEqual(readingWords(words.filter(w => w.id !== 'left-cup'), p.caption).map(w => w.id), ['right-cup', 'full', 'run']);
    const restored = projectSchema.parse(JSON.parse(JSON.stringify({ ...p, words })));
    assert.deepEqual(readingGroups(restored.words, restored.caption), readingGroups(words, p.caption));
});

test('same-object words have contiguous audio and highlights, with follow-along pauses only between groups', () => {
    const words = [
        { ...p.words[0], audioSeconds: .81 },
        { ...p.words[0], id: 'table', english: 'table', audioSeconds: .6 },
        { ...p.words[1], audioSeconds: 1.03 },
        { ...p.words[1], id: 'blue', audioSeconds: .75 },
    ];
    for (const pauseSeconds of [0, 1.2, 3]) {
        const project = { ...p, words, pauseSeconds };
        const segments = timeline(project).words;
        assert.deepEqual(segments.map(s => s.word.id), ['cup', 'empty', 'blue', 'table']);
        assert.equal(segments[0].audioFrom, segments[0].from + AUDIO_LEAD_FRAMES);
        for (let index = 0; index < 2; index++) {
            const current = segments[index], next = segments[index + 1];
            assert.equal(next.audioFrom, current.audioFrom + current.audioFrames);
            assert.equal(current.audioTailFrames, 0);
            assert.equal(activeWord(project, next.audioFrom - 1)?.id, current.word.id);
            assert.equal(activeWord(project, next.audioFrom)?.id, next.word.id);
        }
        const lastAdjective = segments[2], nextObject = segments[3];
        assert.equal(nextObject.audioFrom - (lastAdjective.audioFrom + lastAdjective.audioFrames), AUDIO_TAIL_FRAMES + Math.ceil(pauseSeconds * FPS) + AUDIO_LEAD_FRAMES);
        assert.equal(lastAdjective.audioTailFrames, AUDIO_TAIL_FRAMES);
        for (const segment of segments) assert.ok(segment.audioFrom + segment.audioFrames + segment.audioTailFrames <= segment.from + segment.duration);
    }
});
