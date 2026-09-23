import { test } from 'node:test';
import assert from 'node:assert/strict';
import { emptyProject, clearProjectSpeech, projectSchema, timeline, editCaptionSentence, descriptionSentences, exportBlockers, AUDIO_LEAD_FRAMES, AUDIO_TAIL_FRAMES, FPS, type Project } from './project';
const audio = '/studio-api/assets/abcd.wav';
const project: Project = { ...emptyProject, image: '/studio-api/assets/abcd.jpg', captionReviewRequired: false,
    words: [{ id: 'cup', kind: 'state', english: 'blue', chinese: '蓝色', ipa: '', audio, audioSeconds: 1 }],
    captionSentences: [
        { english: 'A cup sits on the table.', chinese: '桌上放着一个杯子。', audio, audioSeconds: 2.6 },
        { english: 'A plant stands beside it.', chinese: '旁边摆着一盆植物。', audio, audioSeconds: 4.2 },
    ], interaction: { enabled: true, english: 'What is blue?', chinese: '什么是蓝色的？', audio, audioSeconds: 1 },
};
test('round trip joins descriptions and keeps per-sentence audio', () => {
    const p = projectSchema.parse(JSON.parse(JSON.stringify(project)));
    assert.equal(p.caption, 'A cup sits on the table. A plant stands beside it.');
    assert.equal(p.captionChinese, '桌上放着一个杯子。旁边摆着一盆植物。');
    assert.deepEqual(p.captionSentences, project.captionSentences);
    assert.deepEqual(exportBlockers(p), []);
});
test('both templates sequence each real audio duration with protected lead and tail before interaction', () => {
    for (const videoTemplate of ['direct', 'camera'] as const) {
        const t = timeline({ ...project, videoTemplate });
        assert.equal(t.captions[0].from, t.captionFrom);
        for (const item of t.captions) assert.equal(item.duration, AUDIO_LEAD_FRAMES + Math.ceil(item.sentence.audioSeconds! * FPS) + AUDIO_TAIL_FRAMES);
        assert.equal(t.captions[1].from, t.captions[0].from + t.captions[0].duration);
        assert.equal(t.interactionFrom, t.captions[1].from + t.captions[1].duration);
        assert.equal(t.caption, t.captions.reduce((sum, s) => sum + s.duration, 0));
    }
});
test('editing either language removes all caption audio and requires review', () => {
    for (const patch of [{ english: 'A blue cup.' }, { chinese: '蓝色杯子。' }]) {
        const p = editCaptionSentence(project, 0, patch);
        assert.equal(p.captionReviewRequired, true);
        assert.ok(p.captionSentences!.every(s => !s.audio && !s.audioSeconds));
        assert.equal(p.captionAudio, undefined);
        assert.equal(p.socialCopy, undefined);
        assert.ok(exportBlockers(p).length > 0);
    }
});
test('missing second sentence audio blocks export even if legacy audio exists', () => {
    const p = projectSchema.parse({ ...project, captionAudio: audio, captionAudioSeconds: 6, captionSentences: project.captionSentences!.map((s, i) => i ? { ...s, audio: undefined } : s) });
    assert.ok(exportBlockers(p).includes('照片句子尚未生成配音'));
});
test('version three keeps old text and audio as one unsplit segment', () => {
    const legacy = { ...emptyProject, version: 3, caption: 'Dr. Smith has a cup. It is blue.', captionChinese: '史密斯有一个蓝色杯子。', captionReviewRequired: false, captionAudio: audio, captionAudioSeconds: 5 };
    const p = projectSchema.parse(legacy);
    assert.equal(p.version, 4);
    assert.equal(p.caption, legacy.caption);
    assert.equal(p.captionSentences, undefined);
    assert.equal(descriptionSentences(p).length, 1);
    assert.equal(timeline(p).captions[0].sentence.audio, audio);
});

test('changing voice settings clears word, sentence, legacy and interaction audio', () => {
    const p = clearProjectSpeech({ ...project, captionAudio: audio, captionAudioSeconds: 6 });
    assert.ok(p.words.every(w => !w.audio && !w.audioSeconds));
    assert.ok(p.captionSentences!.every(s => !s.audio && !s.audioSeconds));
    assert.equal(p.captionAudio, undefined);
    assert.equal(p.interaction!.audio, undefined);
    assert.equal(p.captionReviewRequired, false);
});
