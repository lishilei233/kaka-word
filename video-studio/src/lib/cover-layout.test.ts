import { test } from 'node:test';
import assert from 'node:assert/strict';
import { coverLayout, coverExportReady } from './cover-layout';
import { emptyProject, projectSchema, type Project } from './project';

const project: Project = { ...emptyProject, image: '/studio-api/assets/aaaaaaaa-aaaa.jpg', imageWidth: 1200, imageHeight: 1600, words: Array.from({ length: 10 }, (_, i) => ({ id: String(i), english: 'window', chinese: '', ipa: '', box: { x: .4, y: .4, width: .1, height: .1 } })) };
test('cover preserves aspect ratio, fills the canvas and retains all object words deterministically', () => {
    for (const [imageWidth, imageHeight] of [[1200,1600],[1600,900],[6000,200]]) {
        const p = { ...project, imageWidth, imageHeight };
        const layout = coverLayout(p);
        assert.equal(layout.objects.length, 10);
        assert.ok(Math.abs(layout.photo.width/layout.photo.height-imageWidth/imageHeight)<1e-8);
        assert.ok(layout.photo.x <= .001 && layout.photo.y <= .001);
        assert.ok(layout.photo.width >= 1080-.001 && layout.photo.height >= 1440-.001);
        assert.deepEqual(layout, coverLayout(p));
    }
});
test('cover exports without speech and ignores legacy manual positions', () => {
    assert.equal(coverExportReady({ ...project, words: project.words.slice(0, 1) }), true);
    const cover = { template: 'learning-card' as const, scale: 1, words: Object.fromEntries(project.words.map(w => [w.id, { scale: 1, labelCenterOverride: { x: .5, y: .5 } }])) };
    assert.equal(coverLayout({ ...project, cover }).objects.length, 10);
    assert.equal(coverExportReady({ ...project, cover }), true);
    assert.equal(coverExportReady({ ...project, imageWidth: 10000, imageHeight: 100 }), true);
});
test('cover title and ordered word rows are independent from video annotation positions', () => {
    const original = structuredClone(project);
    const videoMoved = { ...project, words: project.words.map(w => ({ ...w, labelCenterOverride: { x: .1, y: .1 } })) };
    assert.deepEqual(coverLayout(videoMoved).objects.map(word => word.id), coverLayout(project).objects.map(word => word.id));
    assert.deepEqual(coverLayout(videoMoved).photo, coverLayout(project).photo);
    const cover = { template: 'learning-card' as const, scale: 1.2, words: { '0': { scale: 1.3, labelCenterOverride: { x: .3, y: .3 }, targetCenterOverride: { x: .2, y: .2 } } } };
    const saved = projectSchema.parse({ ...project, cover });
    assert.deepEqual(saved.cover, cover);
    assert.deepEqual(project, original);
    const result = coverLayout({ ...saved, sceneTheme: '安静的舞蹈教室' });
    assert.equal(result.title, '安静的舞蹈教室');
    assert.deepEqual(result.objects.map(word => word.id), project.words.map(word => word.id));
    assert.equal(projectSchema.parse(project).cover, undefined);
});

test('cover separates up to ten object words from a single row of scene words', () => {
    const objects = Array.from({ length: 8 }, (_, index) => ({
        id: `object-${index}`, english: index === 7 ? 'air conditioner' : `object ${index + 1}`,
        chinese: '', ipa: '', kind: 'object' as const, needsLocation: true,
    }));
    const scenes = [
        { id: 'action', english: 'practice', chinese: '', ipa: '', kind: 'action' as const },
        { id: 'state-1', english: 'empty', chinese: '', ipa: '', kind: 'state' as const },
        { id: 'state-2', english: 'shiny', chinese: '', ipa: '', kind: 'state' as const },
        { id: 'state-3', english: 'closed', chinese: '', ipa: '', kind: 'state' as const },
    ];
    const layout = coverLayout({ ...project, sceneTheme: '安静的舞蹈教室', words: [...objects, ...scenes] });
    assert.equal(layout.objects.length, 8);
    assert.equal(layout.scenes.length, 4);
    assert.equal(layout.title, '安静的舞蹈教室');
    assert.equal(layout.objects.at(-1)?.english, 'air conditioner');

    const noScene = coverLayout({ ...project, sceneTheme: undefined, words: project.words.slice(0, 1) });
    assert.equal(noScene.title, project.title);
    assert.deepEqual(noScene.scenes, []);
});
