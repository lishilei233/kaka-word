import { test } from 'node:test';
import assert from 'node:assert/strict';
import { balancedCoverRows, coverLayout, coverExportReady } from './cover-layout';
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

test('cover title override is isolated from the recognized scene theme', () => {
    const saved = projectSchema.parse({
        ...project,
        sceneTheme: '客厅里的休闲时光',
        cover: { template: 'learning-card', title: '周末客厅英语', scale: .9, words: {} },
    });
    assert.equal(coverLayout(saved).title, '周末客厅英语');
    assert.equal(saved.sceneTheme, '客厅里的休闲时光');
    assert.equal(coverLayout({ ...saved, cover: { ...saved.cover!, title: '' } }).title, '客厅里的休闲时光');
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

test('cover balances one to ten capsules into stable rows with at most five items', () => {
    const makeItems = (count: number) => Array.from({ length: count }, (_, order) => ({ value: `word-${order}`, width: 100, order }));
    for (const [count, expectedRows] of [[1,1],[4,1],[5,1],[6,2],[8,2],[10,2]]) {
        const rows = balancedCoverRows(makeItems(count), 600, 14);
        assert.equal(rows.length, expectedRows);
        assert.ok(rows.every(row => row.items.length <= 5));
        assert.ok(Math.max(...rows.map(row => row.items.length)) - Math.min(...rows.map(row => row.items.length)) <= 1);
        assert.deepEqual(rows, balancedCoverRows(makeItems(count), 600, 14));
    }
});

test('cover reorders mixed capsule widths into balanced rows and falls back to three rows', () => {
    const widths = [260, 240, 80, 80, 80, 80, 80, 80, 80, 80];
    const items = widths.map((width, order) => ({ value: `word-${order}`, width, order }));
    const rows = balancedCoverRows(items, 600, 14);
    assert.equal(rows.length, 3);
    assert.ok(rows.every(row => row.width <= 600));
    assert.ok(Math.max(...rows.map(row => row.items.length)) - Math.min(...rows.map(row => row.items.length)) <= 1);
    assert.ok(rows.every(row => row.items.every((item, index) => index === 0 || row.items[index - 1].order < item.order)));
    assert.ok(rows.every((row, index) => index === 0 || rows[index - 1].width >= row.width));
});
