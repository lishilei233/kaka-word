import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { sentencePhrases, activePhraseIndex, phraseEmphasis } from './sentence-phrases';
import { SceneSentence } from '../video/SceneSentence';

test('reading groups preserve original text and repeated multiword vocabulary', () => {
    for (const text of ['', 'Hello!', "It's a cup, beside a trash can and another trash can.", '  Dr. Smith has 2 cups.  ', 'A very long sentence with several everyday objects on the kitchen counter.']) {
        const groups = sentencePhrases(text, ['trash can']);
        assert.equal(groups.map(group => group.text).join(''), text);
        assert.ok(groups.every(group => group.weight > 0));
        if (text.includes('trash can')) assert.equal(groups.filter(group => group.text.includes('trash can')).length, 2);
    }
    assert.deepEqual(sentencePhrases('A cup sits on the table.').map(p => p.text.trim()), ['A cup sits', 'on the table.']);
});

test('highlight follows weighted intervals and clears outside audio', () => {
    const groups = [{ weight: 2 }, { weight: 3 }];
    for (const frame of [-1, 100, NaN, Infinity]) assert.equal(activePhraseIndex(groups, frame, 100), -1);
    assert.equal(activePhraseIndex(groups, 0, 100), 0);
    assert.equal(activePhraseIndex(groups, 39, 100), 0);
    assert.equal(activePhraseIndex(groups, 40, 100), 1);
    assert.equal(activePhraseIndex(groups, 99, 100), 1);
    assert.equal(activePhraseIndex(groups, 0, 0), -1);
    assert.equal(activePhraseIndex(groups), -1);
});

test('rendering changes only phrase backgrounds while preserving layout and underlines', () => {
    const props = { english: 'A cup sits on the table.', chinese: '桌上有一个杯子。', width: 200, vocabulary: ['cup'], audioDurationFrames: 100 };
    const render = (audioFrame?: number) => renderToStaticMarkup(createElement(SceneSentence, { ...props, audioFrame }));
    const idle = render();
    for (const frame of [0, 50, 99]) {
        const html = render(frame);
        assert.equal((html.match(/data-phrase-active="true"/g) ?? []).length, 1);
        assert.equal(html.replace(/ data-phrase-active="true"/g, '').replace(/scale\([\d.]+\)/g, 'scale(1)').replace(/rgba\(255,216,77,[\d.]+\)/g, 'rgba(255,216,77,0)'), idle);
    }
    assert.ok(idle.includes('text-decoration-line:underline'));
    assert.equal(render(-1), idle);
    assert.equal(render(100), idle);
});

test('phrase emphasis eases in and out within its own interval', () => {
    const groups = [{ weight: 1 }, { weight: 1 }];
    assert.equal(phraseEmphasis(groups, 0, 0, 100), 0);
    assert.ok(phraseEmphasis(groups, 0, 2, 100) > 0);
    assert.ok(phraseEmphasis(groups, 0, 2, 100) < 1);
    assert.equal(phraseEmphasis(groups, 0, 25, 100), 1);
    assert.ok(phraseEmphasis(groups, 0, 49, 100) < 1);
    assert.equal(phraseEmphasis(groups, 0, 50, 100), 0);
    assert.equal(phraseEmphasis(groups, 1, 100, 100), 0);
});
