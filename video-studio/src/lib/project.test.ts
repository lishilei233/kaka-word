import { test } from 'node:test';
import assert from 'node:assert/strict';
import { activeWord, AUDIO_LEAD_FRAMES, AUDIO_TAIL_FRAMES, CAPTION_FRAMES, changeEnglish, openingMedia, emptyProject, exportReady, projectSchema, sortByPhotoPosition, timeline, type Project } from './project.ts';
const p: Project = { ...emptyProject, image: '/studio-api/assets/1234.jpg', caption: 'A quiet room.', captionAudio: '/studio-api/assets/abcd.wav', captionAudioSeconds: 1.8, words: [
    { id: '1', english: 'window', chinese: '窗户', ipa: '', box: { x: .05, y: .1, width: .1, height: .2 }, audio: '/studio-api/assets/1234.wav', audioSeconds: .8 },
    { id: '2', english: 'trash can', chinese: '垃圾桶', ipa: '', box: { x: .4, y: .5, width: .2, height: .2 }, audio: '/studio-api/assets/5678.wav', audioSeconds: 1.4 },
] };
test('audio durations determine non-overlapping word segments and exact highlight boundaries', () => {
    const t = timeline(p);
    assert.equal(activeWord(p, t.words[0].from - 1), undefined);
    assert.equal(activeWord(p, t.words[0].from)?.id, '1');
    assert.equal(activeWord(p, t.words[1].from)?.id, '2');
    assert.ok(t.words[1].duration > t.words[0].duration);
    assert.equal(t.words[0].from + t.words[0].duration, t.words[1].from);
    for (const segment of t.words) {
        const protectedAudioEnd = segment.from + AUDIO_LEAD_FRAMES + segment.audioFrames + AUDIO_TAIL_FRAMES;
        assert.ok(protectedAudioEnd <= segment.from + segment.duration);
    }
    assert.equal(t.captionFrom, t.words.at(-1)!.from + t.words.at(-1)!.duration);
    assert.equal(t.caption, Math.max(CAPTION_FRAMES, AUDIO_LEAD_FRAMES + t.captionAudioFrames + AUDIO_TAIL_FRAMES));
    assert.equal(t.total, t.captionFrom + t.caption);
    assert.equal(activeWord(p, t.total - 1), undefined);
});
test('editing text invalidates its speech and blocks export', () => {
    assert.equal(exportReady(p), true);
    const updated = { ...p, words: [changeEnglish(p.words[0], 'door')] };
    assert.equal(updated.words[0].audio, undefined);
    assert.equal(exportReady(updated), false);
});
test('projects reject untrusted asset paths and out-of-range positions', () => {
    assert.equal(projectSchema.safeParse(p).success, true);
    assert.equal(projectSchema.safeParse({ ...p, image: 'http://internal.local/file' }).success, false);
    assert.equal(projectSchema.safeParse({ ...p, words: [{ ...p.words[0], box: { ...p.words[0].box, x: 2 } }] }).success, false);
    assert.equal(projectSchema.safeParse({ ...p, words: [p.words[0], p.words[0]] }).success, false);
});

test('opening video always reaches the selected capture frame without looping', () => {
    for (const captureSeconds of [0, .5, 2, 8]) {
        const project = { ...p, captureSeconds };
        const media = openingMedia(project);
        assert.equal(media.holdFrames + media.playFrames, timeline(project).intro);
        assert.equal(media.startFrom + media.playFrames, Math.round(captureSeconds * 30));
    }
});
test('recognized objects sort by photo rows, then from left to right', () => {
    const objects = [
        { id: 'bottom', box: { x: .1, y: .72, width: .1, height: .1 } },
        { id: 'top-right', box: { x: .7, y: .11, width: .1, height: .1 } },
        { id: 'top-left', box: { x: .1, y: .13, width: .1, height: .1 } },
        { id: 'middle', box: { x: .4, y: .4, width: .1, height: .1 } },
    ];
    assert.deepEqual(sortByPhotoPosition(objects).map(object => object.id), ['top-left', 'top-right', 'middle', 'bottom']);
});
