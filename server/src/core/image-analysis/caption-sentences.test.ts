import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generatedPhotoCaptionSchema, photoCaptionSchema, normalizeCaption } from './types.js';
import { captionGenerationPrompt, captionReviewPrompt, learningObjectPrompt, qwenLearningObjectPrompt } from './prompts.js';
import { studioScenePrompt } from './studio-scene.js';

const sentences = [
  { english: 'A cup and a book sit on the table.', chinese: '桌上放着一个杯子和一本书。' },
  { english: 'A small plant stands beside the book.', chinese: '书旁边摆着一盆小植物。' },
];
const old = { caption: 'Original description.', captionChinese: '原描述。' };
test('one or two paired sentences are authoritative over legacy joined fields', () => {
  for (const captionSentences of [sentences.slice(0, 1), sentences]) {
    const result = generatedPhotoCaptionSchema.parse({ ...old, captionSentences });
    assert.equal(result.caption, captionSentences.map(s => s.english).join(' '));
    assert.equal(result.captionChinese, captionSentences.map(s => s.chinese).join(''));
    assert.deepEqual(result.captionSentences, captionSentences);
  }
});
test('new generation rejects missing, empty, unpaired, too many and overlong sentences', () => {
  for (const captionSentences of [undefined, [], [...sentences, sentences[0]], [{ english: 'A cup.' }], [{ english: '', chinese: '杯子。' }], [{ english: Array(19).fill('word').join(' '), chinese: '描述。' }]]) {
    assert.equal(generatedPhotoCaptionSchema.safeParse({ ...old, captionSentences }).success, false);
  }
  assert.equal(generatedPhotoCaptionSchema.safeParse({ ...old, captionSentences: [{ english: Array(18).fill('word').join(' '), chinese: '描述。' }] }).success, true);
});
test('legacy description remains unchanged and is never split by punctuation', () => {
  const legacy = { caption: 'Dr. Smith has a cup. It is blue.', captionChinese: '史密斯有一个蓝色杯子。' };
  assert.deepEqual(normalizeCaption(photoCaptionSchema.parse(legacy)), legacy);
});
test('every generation and review prompt uses the same paired sentence policy', () => {
  for (const prompt of [learningObjectPrompt(8, 'serious'), qwenLearningObjectPrompt(8, 'funny'), captionGenerationPrompt({ words: [] }), captionReviewPrompt({ ...old, words: [] }), studioScenePrompt({ context: '', objects: [] })]) {
    assert.match(prompt, /captionSentences/);
    assert.match(prompt, /never more than 18/);
    assert.doesNotMatch(prompt, /exactly one beginner-friendly sentence|no more than (24|40) words/);
  }
});
