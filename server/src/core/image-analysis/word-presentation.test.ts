import test from 'node:test';
import assert from 'node:assert/strict';
import { applyVerbEvidence, captionPosition, captionVerbs, finalizeSceneWords } from './word-presentation.js';

test('final caption evidence preserves irregular and phrasal verbs, orders, deduplicates and caps at three', () => {
    const caption = 'She ran, picked up a cup, drank, smiled and ran again.';
    const words = ['smile', 'run', 'drink', 'pick up', 'run', 'be'].map(english => ({ english, kind: 'verb' }));
    const matches = [{ english: 'smile', captionForm: 'smiled' }, { english: 'run', captionForm: 'ran' },
        { english: 'drink', captionForm: 'drank' }, { english: 'pick up', captionForm: 'picked up' }, { english: 'be', captionForm: 'She' }];
    assert.deepEqual(captionVerbs(applyVerbEvidence(words, caption, matches), caption).map(w => w.english), ['run', 'pick up', 'drink']);
    assert.deepEqual(captionVerbs(applyVerbEvidence(words, caption, matches), 'The cup is empty.'), []);
    assert.deepEqual(captionVerbs(words, caption), []);
    assert.equal(captionPosition('A runner holds a running shoe.', 'run'), -1);
    assert.equal(captionPosition('She picks up a cup.', 'picks up'), 1);
});

test('states require an existing positive-sized object and inherit its visible anchor', () => {
    const objects = [{ id: 'cup', box: { x: .1, y: .2, width: .3, height: .4 }, anchor: { x: .2, y: .3 } }];
    const words = [{ english: 'empty', kind: 'adjective', relatedObjectID: 'cup' },
        { english: 'happy', kind: 'adjective' }, { english: 'cold', kind: 'adjective', relatedObjectID: 'missing' }];
    const result = finalizeSceneWords(words, objects, 'A cup.', [], 5);
    assert.equal(result.length, 1);
    assert.deepEqual(result[0].box, objects[0].box);
    assert.deepEqual(result[0].anchor, objects[0].anchor);
    assert.deepEqual(finalizeSceneWords(words, [], 'A cup.', [], 5), []);
});

test('word must be confirmed as a verb after review, not a participial adjective or auxiliary', () => {
    const words = [{ english: 'break', kind: 'verb', captionForm: 'broken' }];
    assert.deepEqual(captionVerbs(applyVerbEvidence(words, 'The cup is broken.', []), 'The cup is broken.'), []);
});

test('full and empty stay attached to their own cups without being required in the caption', () => {
    const objects = ['filled-cup', 'empty-cup', 'plate'].map((id, index) => ({ id, box: { x: index * .3, y: .1, width: .2, height: .3 } }));
    const words = [{ english: 'full', kind: 'adjective', relatedObjectID: 'filled-cup' }, { english: 'empty', kind: 'adjective', relatedObjectID: 'empty-cup' }];
    const result = finalizeSceneWords(words, objects, 'Two cups and a plate sit on a table.', [], 5);
    assert.deepEqual(result.map(w => [w.english, w.relatedObjectID, w.box]), [
        ['full', 'filled-cup', objects[0].box], ['empty', 'empty-cup', objects[1].box],
    ]);
    assert.deepEqual(finalizeSceneWords([], objects, 'A plate.', [], 5), []);
});
