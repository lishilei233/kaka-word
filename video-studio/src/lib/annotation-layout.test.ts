import { test } from 'node:test';
import assert from 'node:assert/strict';
import { annotationLayout, type AnnotationObject, type Box } from './annotation-layout.ts';

const frame: Box = { x: 0, y: 0, width: 360, height: 480 };
const makeObject = (id: string, index=0): AnnotationObject => ({
    id, english: `long-word-${index}`, box: { x: .43+(index%2)*.02, y: .43+Math.floor(index/2)*.01, width: .12, height: .12 },
});
function overlap(a: Box,b: Box) { return a.x < b.x+b.width && a.x+a.width > b.x && a.y < b.y+b.height && a.y+a.height > b.y; }
function assertNoOverlap(objects: AnnotationObject[], targetFrame=frame) {
    const placements=annotationLayout(objects,targetFrame).placements;
    for(let i=0;i<placements.length;i++) for(let j=i+1;j<placements.length;j++) assert.equal(overlap(placements[i].labelFrame,placements[j].labelFrame),false);
    return placements;
}

test('ten clustered automatic labels remain non-overlapping and inside the image', () => {
    const placements=assertNoOverlap(Array.from({length:10},(_,i)=>makeObject(`object-${i}`,i)));
    assert.equal(placements.length,10);
    for(const p of placements) assert.ok(p.labelFrame.x>=0&&p.labelFrame.y>=0&&p.labelFrame.x+p.labelFrame.width<=360&&p.labelFrame.y+p.labelFrame.height<=480);
});

test('identical manual positions separate, while the actively moved label stays fixed', () => {
    const objects=Array.from({length:4},(_,i)=>({...makeObject(`manual-${i}`,i),labelCenterOverride:{x:.5,y:.5}}));
    assert.equal(assertNoOverlap(objects).length,4);
    const layout=annotationLayout(objects,frame,'manual-2');
    const moved=layout.placements.find(p=>p.id==='manual-2')!;
    assert.equal(moved.labelCenter.x,180); assert.equal(moved.labelCenter.y,240);
    for(const other of layout.placements.filter(p=>p.id!=='manual-2')) assert.equal(overlap(moved.labelFrame,other.labelFrame),false);
});

test('an impossible frame omits labels instead of overlapping them', () => {
    const objects=Array.from({length:8},(_,i)=>makeObject(`tiny-${i}`,i));
    const placements=assertNoOverlap(objects,{x:0,y:0,width:180,height:80});
    assert.ok(placements.length<objects.length);
});

test('routes target box centers, start on capsule edges and avoid other labels', () => {
    const objects=Array.from({length:8},(_,i)=>makeObject(`route-${i}`,i));
    const layout=annotationLayout(objects,frame);
    for(const route of layout.routes) {
        const object=objects.find(o=>o.id===route.id)!;
        assert.ok(Math.abs(route.target.x-(object.box.x+object.box.width/2)*frame.width)<1e-6);
        assert.ok(Math.abs(route.target.y-(object.box.y+object.box.height/2)*frame.height)<1e-6);
        const placement=layout.placements.find(p=>p.id===route.id)!;
        assert.ok(route.start.x===placement.labelFrame.x||route.start.x===placement.labelFrame.x+placement.labelFrame.width||route.start.y===placement.labelFrame.y||route.start.y===placement.labelFrame.y+placement.labelFrame.height);
        assert.ok(Math.hypot(route.control.x-(route.start.x+route.target.x)/2,route.control.y-(route.start.y+route.target.y)/2)>1);
        for(const obstacle of layout.placements.filter(p=>p.id!==route.id)) for(const point of route.samples.slice(1)) assert.equal(point.x>=obstacle.labelFrame.x-2&&point.x<=obstacle.labelFrame.x+obstacle.labelFrame.width+2&&point.y>=obstacle.labelFrame.y-2&&point.y<=obstacle.labelFrame.y+obstacle.labelFrame.height+2,false);
    }
});

test('a manual leader-line target overrides the detected box center', () => {
    const object = { ...makeObject('target'), targetCenterOverride: { x: .18, y: .82 } };
    const route = annotationLayout([object], frame).routes[0];
    assert.equal(route.target.x, frame.width * .18);
    assert.equal(route.target.y, frame.height * .82);
});

test('portrait, landscape and panoramic layouts are deterministic', () => {
    const objects=Array.from({length:6},(_,i)=>makeObject(`aspect-${i}`,i));
    for(const targetFrame of [{x:0,y:0,width:280,height:480},{x:0,y:0,width:480,height:280},{x:0,y:0,width:500,height:120}]) {
        assert.deepEqual(annotationLayout(objects,targetFrame),annotationLayout(objects,targetFrame));
        assertNoOverlap(objects,targetFrame);
    }
});
