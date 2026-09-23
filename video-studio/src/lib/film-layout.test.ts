import { test } from 'node:test';
import assert from 'node:assert/strict';
import { emptyProject, projectSchema } from './project.ts';
import { FILM_HEIGHT, FILM_WIDTH, filmLayout } from './film-layout.ts';

test('result photo keeps its source aspect ratio with 10 point side margins', () => {
    const l = filmLayout(emptyProject);
    assert.deepEqual(l.camera, { x: 0, y: 0, width: FILM_WIDTH, height: FILM_HEIGHT });
    assert.equal(l.viewfinder.x + l.viewfinder.width / 2, l.cameraImage.x + l.cameraImage.width / 2);
    assert.equal(l.viewfinder.y + l.viewfinder.height / 2, l.cameraImage.y + l.cameraImage.height / 2);
    assert.ok(l.viewfinder.width < l.cameraImage.width);
    assert.ok(l.viewfinder.height < l.cameraImage.height);
    assert.equal(l.photo.x, 10);
    assert.equal(l.photo.width, FILM_WIDTH - 20);
    assert.deepEqual(l.photoImage, l.photo);
    assert.equal(l.cameraImage.width/l.cameraImage.height, 4/3);
    assert.equal(l.photoImage.width/l.photoImage.height, 4/3);
});
test('result photo size is independent of scene cards and configurable safe areas', () => {
    for (const safeTop of [120,180,280]) for (const safeBottom of [240,360,480]) for (const aspect of [4/3,3]) {
        const p = { ...emptyProject, safeTop, safeBottom, imageWidth: aspect*100, imageHeight:100 };
        const l = filmLayout(p);
        assert.equal(l.photo.x, 10);
        assert.equal(l.photo.width, 520);
        assert.ok(Math.abs(l.photo.height - 520/aspect) < 1e-10);
        assert.ok(l.descriptionTop >= 0 && l.descriptionTop+140 <= FILM_HEIGHT);
        assert.ok(l.wordTop >= 0 && l.wordTop+l.wordDetailHeight <= FILM_HEIGHT);
        assert.ok(l.shutterTop+104 <= 960-safeBottom/2);
    }
});
test('portrait photos keep the original card size and use visible overlay fallbacks', () => {
    const l = filmLayout({ ...emptyProject, imageWidth: 9, imageHeight: 16 });
    assert.equal(l.photo.width, 520);
    assert.equal(l.photo.height, 520*16/9);
    assert.ok(l.photo.y >= 0 && l.photo.y+l.photo.height <= FILM_HEIGHT);
    assert.ok(l.descriptionTop+140 <= FILM_HEIGHT);
    assert.ok(l.wordTop+l.wordDetailHeight <= FILM_HEIGHT);
    assert.equal(l.descriptionOverPhoto, true);
    assert.equal(l.wordOverPhoto, true);
    assert.equal(l.photo.width / l.photo.height, 9 / 16);
});
test('old drafts migrate label and target coordinates while receiving new defaults', () => {
    const {caption,captionChinese,safeTop,safeBottom,safeRight,version,words,...rest}=emptyProject;
    const restored=projectSchema.parse({ ...rest, version: 1, words: [{ id:'old', english:'lamp', chinese:'灯', ipa:'', x:.2, y:.3, targetX:.6, targetY:.7 }] });
    assert.equal(restored.version,3); assert.equal(restored.caption,''); assert.equal(restored.captionReviewRequired,true); assert.equal(restored.safeTop,120); assert.equal(restored.safeBottom,240);
    assert.deepEqual(restored.words[0].labelCenterOverride,{x:.2,y:.3});
    assert.deepEqual(restored.words[0].targetCenterOverride,{x:.6,y:.7});
    assert.deepEqual(restored.words[0].box,{x:.6,y:.7,width:0,height:0});
});
