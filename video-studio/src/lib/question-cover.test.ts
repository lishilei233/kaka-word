import { test } from 'node:test';
import assert from 'node:assert/strict';
import { emptyProject, projectSchema, type Project } from './project';
import { applyCoverCandidates, cleanCoverSelection, coverCopySource, coverExportReady, coverQuestionTitle, defaultCover, fitCoverTitle, isQuestionCover, moveCoverPhoto, questionCoverLayout, selectedCoverWords } from './cover-layout';

const project: Project = { ...emptyProject, image: '/studio-api/assets/aaaaaaaa-aaaa.jpg', imageWidth: 1200, imageHeight: 1600, sceneTheme: '酒店抽屉', caption: 'A mug.', words: ['mug', 'electric kettle', 'mineral water', 'sugar'].map((english, index) => ({ id: String(index), english, chinese: '', ipa: '', box: { x: .2, y: .2, width: .1, height: .1 } })) };
test('legacy configuration stays legacy while unconfigured projects use question covers', () => {
    assert.equal(isQuestionCover(projectSchema.parse(project)), true);
    const old = projectSchema.parse({ ...project, cover: { scale: .9, words: {}, title: '老标题' } });
    assert.equal(old.cover?.template, 'learning-card');
    assert.equal(isQuestionCover(old), false);
    assert.equal(old.cover?.title, '老标题');
    assert.equal(old.version, 4);
});
test('legacy audience titles remain stored but the shared scene determines the title', () => {
    const original = structuredClone(project);
    const edited = { ...project, cover: { ...defaultCover, audienceTitles: { adult: '杯子英语怎么说？', family: '和孩子认杯子？', student: '这个单词你会吗？' } } };
    for (const audience of ['adult', 'family', 'student'] as const) assert.equal(coverQuestionTitle({ ...edited, cover: { ...edited.cover, audience } }), '酒店抽屉，你会几个单词？');
    assert.deepEqual(project, original);
    const { cover: _cover, ...video } = edited;
    assert.deepEqual(video, project);
});
test('selection defaults to highlighted words, respects empty selection and cleans removed IDs', () => {
    const highlighted = { ...project, cover: { ...defaultCover, words: { '3': { scale: 1, highlighted: true } } } };
    assert.deepEqual(selectedCoverWords(highlighted).map(word => word.id), ['3', '0', '1']);
    assert.deepEqual(selectedCoverWords({ ...highlighted, cover: { ...highlighted.cover, selectedWordIds: [] } }), []);
    const selected = { ...highlighted, cover: { ...highlighted.cover, selectedWordIds: ['0', '3'] } };
    const cleaned = cleanCoverSelection({ ...selected, words: project.words.slice(0, 3) });
    assert.deepEqual(cleaned.cover?.selectedWordIds, ['0']);
    assert.deepEqual(cleaned.cover?.words, {});
});
test('crop fills canvas at all positions for landscape, portrait and extreme aspect ratios', () => {
    for (const [imageWidth, imageHeight] of [[1600, 900], [900, 1600], [6000, 200], [200, 6000]]) {
        for (const zoom of [1, 2]) for (const x of [0, .5, 1]) for (const y of [0, .5, 1]) {
            const p = { ...project, imageWidth, imageHeight, cover: { ...defaultCover, photo: { zoom, x, y } } };
            const { photo } = questionCoverLayout(p);
            assert.ok(photo.x <= 0 && photo.y <= 0);
            assert.ok(photo.x + photo.width >= 1080 - .001 && photo.y + photo.height >= 1440 - .001);
            assert.ok(Math.abs(photo.width / photo.height - imageWidth / imageHeight) < 1e-8);
            const moved = moveCoverPhoto(p, 100000, -100000);
            assert.ok(moved.x >= 0 && moved.x <= 1 && moved.y >= 0 && moved.y <= 1);
        }
    }
});
test('title fits in two explicit lines or blocks export without silently truncating', () => {
    assert.deepEqual(fitCoverTitle('洗手台，英语怎么说？').lines, ['洗手台，', '英语怎么说？']);
    for (const title of ['酒店里的这些东西\n英语怎么说？', '酒店抽屉里的东西，英语怎么说？', 'What is in the drawer?']) {
        const result = fitCoverTitle(title);
        assert.equal(result.fits, true);
        assert.ok(result.lines.length <= 2);
    }
    for (const publishingScene of ['', '很'.repeat(29), '很'.repeat(30)]) {
        const p = { ...project, publishingScene };
        assert.equal(coverExportReady(p), false);
        assert.ok(questionCoverLayout(p).conflicts.length > 0);
    }
});
test('zero to three words render fully; excessive phrase width blocks export', () => {
    for (const count of [0, 1, 2, 3]) {
        const p = { ...project, cover: { ...defaultCover, selectedWordIds: project.words.slice(0, count).map(word => word.id) } };
        assert.equal(questionCoverLayout(p).words.length, count);
        assert.equal(coverExportReady(p), true);
    }
    const p = { ...project, words: [{ ...project.words[0], english: 'W'.repeat(60) }] };
    assert.equal(coverExportReady(p), false);
});
test('candidate updates preserve manual titles and discard changed content or photo', () => {
    const p = { ...project, cover: { ...defaultCover, audienceTitles: { adult: '手写标题？' } } };
    const source = coverCopySource(p);
    const candidates = { adult: ['a', 'b', 'c'], family: ['d', 'e', 'f'], student: ['g', 'h', 'i'] };
    assert.deepEqual(applyCoverCandidates(p, source, candidates).cover?.audienceTitles, p.cover.audienceTitles);
    for (const changed of [{ ...p, image: '/studio-api/assets/bbbbbbbb-bbbb.jpg' }, { ...p, caption: 'New caption.' }]) assert.equal(applyCoverCandidates(changed, source, candidates), changed);
});
