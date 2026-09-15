import { test } from 'node:test';
import assert from 'node:assert/strict';
import { coverLayout, coverExportReady } from './cover-layout';
import { emptyProject, projectSchema, type Project } from './project';

const project: Project = { ...emptyProject, image: '/studio-api/assets/aaaaaaaa-aaaa.jpg', imageWidth: 1200, imageHeight: 1600, words: Array.from({ length: 10 }, (_, i) => ({ id: String(i), english: 'window', chinese: '', ipa: '', box: { x: .4, y: .4, width: .1, height: .1 } })) };
test('cover preserves aspect ratio, fills the canvas without margins and retains all words deterministically', () => {
    for (const [imageWidth, imageHeight] of [[1200,1600],[1600,900],[6000,200]]) {
        const p = { ...project, imageWidth, imageHeight };
        const layout = coverLayout(p);
        assert.equal(layout.placements.length, 10);
        assert.ok(Math.abs(layout.photo.width/layout.photo.height-imageWidth/imageHeight)<1e-8);
        assert.ok(layout.photo.x <= .001 && layout.photo.y <= .001);
        assert.ok(layout.photo.width >= 1080-.001 && layout.photo.height >= 1440-.001);
        assert.deepEqual(layout, coverLayout(p));
    }
});
test('cover exports without speech and blocks overlapping overrides and oversized labels', () => {
    assert.equal(coverExportReady({ ...project, words: project.words.slice(0, 1) }), true);
    const cover = { template: 'learning-card' as const, scale: 1, words: Object.fromEntries(project.words.map(w => [w.id, { scale: 1, labelCenterOverride: { x: .5, y: .5 } }])) };
    assert.equal(coverLayout({ ...project, cover }).placements.length, 10);
    assert.equal(coverExportReady({ ...project, cover }), false);
    assert.equal(coverExportReady({ ...project, imageWidth: 10000, imageHeight: 100 }), false);
});
test('cover adjustments inherit video positions and persist without changing video data', () => {
    const original = structuredClone(project);
    const videoMoved = { ...project, words: project.words.map(w => ({ ...w, labelCenterOverride: { x: .1, y: .1 } })) };
    assert.notDeepEqual(coverLayout(videoMoved), coverLayout(project));
    const cover = { template: 'learning-card' as const, scale: 1.2, words: { '0': { scale: 1.3, labelCenterOverride: { x: .3, y: .3 }, targetCenterOverride: { x: .2, y: .2 } } } };
    const saved = projectSchema.parse({ ...project, cover });
    assert.deepEqual(saved.cover, cover);
    assert.deepEqual(project, original);
    const result = coverLayout(saved).placements[0];
    assert.ok(Math.abs(result.labelHeight-42*2*1.2*1.3)<1e-8);
    assert.equal(result.target.x, coverLayout(saved).photo.x+coverLayout(saved).photo.width*.2);
    assert.equal(projectSchema.parse(project).cover, undefined);
});
