import test from 'node:test';
import assert from 'node:assert/strict';
import { vocabularyKindSchema, vocabularyResponse, nonNounKindSchema } from './vocabulary-kind.js';
import { studioSceneSchema } from './studio-scene.js';

test('all legacy parts of speech normalize and unknown classifications fail closed', () => {
    for (const [legacy, canonical] of [['object', 'noun'], ['state', 'adjective'], ['action', 'verb']]) {
        assert.equal(vocabularyKindSchema.parse(legacy), canonical);
        assert.equal(vocabularyKindSchema.parse(canonical), canonical);
    }
    assert.equal(vocabularyKindSchema.safeParse('adverb').success, false);
    assert.equal(nonNounKindSchema.safeParse('object').success, false);
});

test('wire format changes only kind fields and preserves identifiers and evidence', () => {
    const words = [{ id: 'state', kind: 'adjective', relatedObjectID: 'object', english: 'empty' }, { id: 'action', kind: 'verb', captionForm: 'ran', captionEvidence: 'She ran.' }];
    const legacy = { sceneWords: words.map(w => ({ ...w, kind: w.kind === 'verb' ? 'action' : 'state' })) };
    assert.deepEqual(vocabularyResponse({ sceneWords: words }), legacy);
    assert.deepEqual(vocabularyResponse(legacy, 'pos-v1'), { sceneWords: words });
    assert.deepEqual(words.map(w => w.kind), ['adjective', 'verb']);
});

test('legacy AI classifications normalize before discriminated validation', () => {
    const result = studioSceneSchema.parse({ theme: '杯子', caption: 'An empty cup.', captionChinese: '一个空杯子。', interaction: { english: 'What is here?', chinese: '这里有什么？' }, words: [{ id: 'state', kind: 'state', relatedObjectID: 'object', english: 'empty', chinese: '空的', ipa: '' }] });
    assert.equal(result.words[0].kind, 'adjective');
    assert.equal(result.words[0].relatedObjectID, 'object');
});
