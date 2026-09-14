import { test } from 'node:test';
import assert from 'node:assert/strict';
import { emptyProject, projectSchema } from './project.ts';
import { FILM_HEIGHT, FILM_WIDTH, filmLayout } from './film-layout.ts';

test('result photo keeps its source aspect ratio with 20 point side margins', () => {
    const l = filmLayout(emptyProject);
    assert.deepEqual(l.camera, { x: 0, y: 0, width: FILM_WIDTH, height: FILM_HEIGHT });
    assert.equal(l.photo.x, 20);
    assert.equal(l.photo.width, FILM_WIDTH - 40);
    assert.deepEqual(l.photoImage, l.photo);
    assert.equal(l.cameraImage.width/l.cameraImage.height, 4/3);
    assert.equal(l.photoImage.width/l.photoImage.height, 4/3);
});
test('caption, word and shutter stay within configurable vertical safe areas', () => {
    for (const safeTop of [120,180,280]) for (const safeBottom of [240,360,480]) for (const aspect of [4/3,3]) {
        const p = { ...emptyProject, safeTop, safeBottom, imageWidth: aspect*100, imageHeight:100 };
        const l = filmLayout(p);
        assert.ok(l.photo.y >= l.top);
        assert.ok(l.photo.y + l.photo.height < l.descriptionTop);
        assert.equal(l.wordTop, l.descriptionTop);
        assert.ok(l.descriptionTop + 140 <= l.closingTop);
        assert.ok(l.wordTop+92 <= 960-safeBottom/2);
        assert.ok(l.shutterTop+104 <= 960-safeBottom/2);
    }
});
test('portrait photos derive height only from their aspect ratio', () => {
    const l = filmLayout({ ...emptyProject, imageWidth: 9, imageHeight: 16 });
    assert.equal(l.photo.width, FILM_WIDTH - 40);
    assert.equal(l.photo.height, (FILM_WIDTH - 40) / (9 / 16));
    assert.equal(l.photo.width / l.photo.height, 9 / 16);
});
test('old drafts migrate label and target coordinates while receiving new defaults', () => {
    const {caption,captionChinese,safeTop,safeBottom,safeRight,version,words,...rest}=emptyProject;
    const restored=projectSchema.parse({ ...rest, version: 1, words: [{ id:'old', english:'lamp', chinese:'灯', ipa:'', x:.2, y:.3, targetX:.6, targetY:.7 }] });
    assert.equal(restored.version,2); assert.equal(restored.caption,''); assert.equal(restored.safeTop,120); assert.equal(restored.safeBottom,240);
    assert.deepEqual(restored.words[0].labelCenterOverride,{x:.2,y:.3});
    assert.deepEqual(restored.words[0].targetCenterOverride,{x:.6,y:.7});
    assert.deepEqual(restored.words[0].box,{x:.6,y:.7,width:0,height:0});
});
