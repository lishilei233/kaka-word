import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { SceneCards, sceneCardFontSize, sceneCardWidth } from '../video/SceneCards';
import { emptyProject, projectSchema, objectWords, sceneWords, timeline, exportBlockers, type Project } from './project';
import { filmLayout } from './film-layout';
import { coverLayout, coverExportReady } from './cover-layout';
import { learningPost } from './learning-post';
import { interactionArrowGeometry } from '../video/InteractionArrow';

const audio = '/studio-api/assets/abcd.wav';
const project: Project = { ...emptyProject, image: '/studio-api/assets/abcd.jpg', caption: 'The shell is broken.', captionChinese: '蛋壳破了。', captionAudio: audio, captionAudioSeconds: 2,
    words: [
        { id: 'state', kind: 'state', english: 'broken', chinese: '破碎的', ipa: '/ˈbroʊkən/', audio, audioSeconds: 1 },
        { id: 'egg', kind: 'object', english: 'egg', chinese: '鸡蛋', ipa: '/eɡ/', box: { x: .2, y: .2, width: .2, height: .2 }, audio, audioSeconds: 1 },
        { id: 'action', kind: 'action', english: 'break', chinese: '打破', ipa: '/breɪk/', audio, audioSeconds: 1 },
    ], interaction: { enabled: false, english: 'Who made this mess?', chinese: '谁把这里弄乱了？' } };

test('scene draft round trip preserves speech, optional coordinates and disabled interaction', () => {
    const restored = projectSchema.parse(JSON.parse(JSON.stringify(project)));
    assert.equal(objectWords(restored.words).length, 1);
    assert.equal(sceneWords(restored.words).length, 2);
    assert.equal(restored.words[0].box, undefined);
    assert.equal(restored.captionAudio, audio);
    assert.deepEqual(restored.interaction, project.interaction);
    assert.deepEqual(exportBlockers(restored), []);
    const legacy = projectSchema.parse({ ...project, analysisMode: undefined, words: [project.words[1]] });
    assert.equal(legacy.analysisMode ?? 'objects', 'objects');
});

test('timeline reads objects before manually ordered scene words and protects interaction audio', () => {
    const enabled = { ...project, interaction: { ...project.interaction!, enabled: true, audio, audioSeconds: 4 } };
    const t = timeline(enabled);
    assert.deepEqual(t.words.map(w => w.word.id), ['egg', 'state', 'action']);
    assert.equal(t.interactionFrom, t.captionFrom + t.caption);
    assert.ok(t.total >= t.interactionFrom + 6 + 120 + 9);
    assert.equal(timeline(project).interaction, 0);
    assert.ok(exportBlockers({ ...enabled, interaction: { ...enabled.interaction, audio: undefined } }).includes('互动句尚未生成配音'));
});

test('scene-card highlight keeps width, grows upward and enlarges text', () => {
    const base = renderToStaticMarkup(createElement(SceneCards, { project }));
    const highlighted = renderToStaticMarkup(createElement(SceneCards, { project, currentId: 'state' }));
    assert.equal(sceneCardWidth('broken'), 104);
    assert.equal(sceneCardWidth('supercalifragilisticexpialidocious'), 235);
    assert.ok(sceneCardFontSize('supercalifragilisticexpialidocious', true) < 20);
    assert.ok(base.includes('width:104px;height:44px'));
    assert.ok(highlighted.includes('width:104px;height:44px'));
    assert.ok(base.includes('bottom:0;width:100%;height:44px'));
    assert.ok(highlighted.includes('bottom:0;width:100%;height:54px'));
    assert.ok(highlighted.includes('font-size:20px'));
    assert.ok(highlighted.includes('0 0 0 3px rgba(255,255,255,.94)'));
    assert.ok(!highlighted.includes('text-overflow:ellipsis'));
    assert.ok(!base.includes('<path'));
    assert.ok(base.includes('broken') && !base.includes('破碎的') && !base.includes('状态'));
});

test('interaction arrow position survives drafts and creates deterministic geometry', () => {
    const withArrow = { ...project, interaction: { ...project.interaction!, enabled: true, arrowEnabled: true, arrowTarget: { x: .77, y: .22 } } };
    const restored = projectSchema.parse(JSON.parse(JSON.stringify(withArrow)));
    assert.deepEqual(restored.interaction?.arrowTarget, { x: .77, y: .22 });
    const first = interactionArrowGeometry({ x: 270, y: 800 }, { x: 405, y: 260 });
    assert.deepEqual(first, interactionArrowGeometry({ x: 270, y: 800 }, { x: 405, y: 260 }));
    assert.match(first.path, /^M 270 800 Q /);
    assert.equal(first.head.split(' ').length, 3);
});

test('up to ten scene cards float inside an unchanged portrait, landscape or panorama photo', () => {
    for (const count of [0, 3, 6, 10]) for (const aspect of [9/16, 4/3, 4]) {
        const p = { ...project, safeTop: 280, safeBottom: 480, safeRight: 160, imageWidth: aspect * 100, imageHeight: 100,
            words: Array.from({ length: count }, (_, i) => ({ ...project.words[0], id: String(i) })) };
        const layout = filmLayout(p);
        assert.ok(Math.abs(layout.photo.width / layout.photo.height - aspect) < 1e-10);
        assert.equal(layout.photo.width, 500);
        assert.ok(layout.descriptionTop + 140 <= 960);
        assert.ok(layout.wordTop + layout.wordDetailHeight <= 960);
        if (count) {
            assert.ok(layout.sceneTop >= 0);
            assert.ok(layout.sceneTop + layout.sceneHeight <= layout.photo.y + layout.photo.height);
            assert.equal(layout.sceneLeft, layout.photo.x + 12);
            assert.equal(layout.sceneWidth, layout.photo.width - 24);
        }
        const cover = coverLayout(p);
        assert.equal(cover.placements.length, 0);
        assert.equal(cover.sceneTop + cover.sceneHeight, 1416);
        assert.equal(cover.sceneLeft, 24);
        assert.equal(cover.sceneWidth, 1032);
        assert.ok(cover.photo.x <= 0 && cover.photo.y <= 0);
        assert.ok(cover.photo.width >= 1080 && cover.photo.height >= 1440);
    }
});

test('cover shows scene words without speech or fake photo markers; pending locations block export', () => {
    assert.deepEqual(coverLayout(project).placements.map(p => p.id), ['egg']);
    assert.equal(coverExportReady(project), true);
    const pending = { ...project, words: [{ ...project.words[0], kind: 'object' as const, needsLocation: true }] };
    assert.equal(projectSchema.safeParse(pending).success, true);
    assert.equal(coverExportReady(pending), false);
    assert.ok(exportBlockers(pending).includes('物体词需要完成定位'));
});

test('learning post uses exact final vocabulary, IPA, meanings and both sentence languages', () => {
    const body = learningPost(project);
    for (const word of project.words) assert.ok(body.includes(`${word.english} ${word.ipa} ${word.chinese}`));
    assert.ok(body.indexOf('egg') < body.indexOf('broken'));
    assert.ok(body.includes(project.captionChinese));
    assert.ok(body.includes(project.interaction!.chinese));
});
