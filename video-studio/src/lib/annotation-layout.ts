export type Point = { x: number; y: number };
export type Box = { x: number; y: number; width: number; height: number };
export type AnnotationObject = { id: string; english: string; box: Box; labelCenterOverride?: Point; targetCenterOverride?: Point; labelScale?: number; labelWidthOverride?: number };
export type Placement<T extends AnnotationObject = AnnotationObject> = {
    id: string; object: T; target: Point; labelCenter: Point; labelWidth: number; labelHeight: number; labelFrame: Box; anchor: Point;
};
export type Route = { id: string; start: Point; control: Point; target: Point; samples: Point[] };
export type AnnotationLayout<T extends AnnotationObject = AnnotationObject> = { placements: Placement<T>[]; routes: Route[] };

const LABEL_HEIGHT = 42;
const SPACING = 4;
const SAFE_DISTANCE = 12;
const EDGE_INSET = 10;
const BEAM_WIDTH = 240;

function clamp(value: number, min: number, max: number) { return Math.min(Math.max(value, min), max); }
function distance(a: Point, b: Point) { return Math.hypot(a.x - b.x, a.y - b.y); }
function center(box: Box): Point { return { x: box.x + box.width / 2, y: box.y + box.height / 2 }; }
function contains(box: Box, p: Point) { return p.x >= box.x && p.x <= box.x + box.width && p.y >= box.y && p.y <= box.y + box.height; }
function inset(box: Box, amount: number): Box { return { x: box.x + amount, y: box.y + amount, width: box.width - amount * 2, height: box.height - amount * 2 }; }
function intersects(a: Box, b: Box) { return a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y; }

function measuredTextWidth(word: string, deterministic = false): number {
    if (!deterministic && typeof document !== 'undefined') {
        const canvas = document.createElement('canvas');
        const context = canvas.getContext('2d');
        if (context) { context.font = '900 16px "SF Pro Rounded", ui-rounded, system-ui, sans-serif'; return Math.ceil(context.measureText(word).width); }
    }
    return Math.ceil([...word].reduce((sum, character) => sum + (/[^\x00-\xff]/.test(character) ? 14 : /[MW@#%]/.test(character) ? 12 : /[ilI1.,' ]/.test(character) ? 4.5 : 8), 0));
}

export function wordLabelWidth(word: string, frame: Box, scale = 1, deterministic = false) {
    return Math.min(Math.max(72, measuredTextWidth(word, deterministic) + 32), Math.min(180, frame.width * .5)) * scale;
}

function targetPoint(object: AnnotationObject, frame: Box): Point {
    const target = object.targetCenterOverride ?? center(object.box);
    return { x: frame.x + frame.width * target.x, y: frame.y + frame.height * target.y };
}

function makePlacement<T extends AnnotationObject>(object: T, raw: Point, target: Point, width: number, frame: Box): Placement<T> {
    const height = LABEL_HEIGHT * (object.labelScale ?? 1);
    const labelCenter = {
        x: clamp(raw.x, frame.x + EDGE_INSET + width / 2, frame.x + frame.width - EDGE_INSET - width / 2),
        y: clamp(raw.y, frame.y + EDGE_INSET + height / 2, frame.y + frame.height - EDGE_INSET - height / 2),
    };
    const labelFrame = { x: labelCenter.x - width / 2, y: labelCenter.y - height / 2, width, height };
    const edges = [
        { x: labelCenter.x, y: labelFrame.y }, { x: labelCenter.x, y: labelFrame.y + labelFrame.height },
        { x: labelFrame.x, y: labelCenter.y }, { x: labelFrame.x + labelFrame.width, y: labelCenter.y },
    ];
    return { id: object.id, object, target, labelCenter, labelWidth: width, labelHeight: height, labelFrame, anchor: edges.sort((a, b) => distance(a, target) - distance(b, target))[0] };
}

function placementCandidates<T extends AnnotationObject>(object: T, target: Point, frame: Box, objectCount: number, movableObjectId?: string): Placement<T>[] {
    const height = LABEL_HEIGHT * (object.labelScale ?? 1);
    const width = object.labelWidthOverride ?? wordLabelWidth(object.english, frame, object.labelScale, object.labelScale !== undefined);
    const preferred = object.labelCenterOverride
        ? { x: frame.x + frame.width * object.labelCenterOverride.x, y: frame.y + frame.height * object.labelCenterOverride.y }
        : target;
    if (object.labelCenterOverride && object.id === movableObjectId) return [makePlacement(object, preferred, target, width, frame)];
    const primary: Point[] = object.labelCenterOverride ? [preferred] : (() => {
        const objectFrame = { x: frame.x + frame.width * object.box.x, y: frame.y + frame.height * object.box.y, width: frame.width * object.box.width, height: frame.height * object.box.height };
        const h = width / 2 + 14, v = height / 2 + 14;
        return [
            { x: objectFrame.x + objectFrame.width + h, y: objectFrame.y + objectFrame.height / 2 },
            { x: objectFrame.x - h, y: objectFrame.y + objectFrame.height / 2 },
            { x: objectFrame.x + objectFrame.width / 2, y: objectFrame.y - v },
            { x: objectFrame.x + objectFrame.width / 2, y: objectFrame.y + objectFrame.height + v },
            { x: objectFrame.x + objectFrame.width + h, y: objectFrame.y - v },
            { x: objectFrame.x - h, y: objectFrame.y - v },
            { x: objectFrame.x + objectFrame.width + h, y: objectFrame.y + objectFrame.height + v },
            { x: objectFrame.x - h, y: objectFrame.y + objectFrame.height + v },
            { x: target.x + h, y: target.y - v * 1.7 }, { x: target.x - h, y: target.y + v * 1.7 },
            { x: target.x + h, y: target.y + v * 1.7 }, { x: target.x - h, y: target.y - v * 1.7 },
        ];
    })();
    const hs = width + SPACING + 4, vs = height + SPACING + 4;
    const offsets = [[hs,0],[-hs,0],[0,vs],[0,-vs],[hs,vs],[-hs,vs],[hs,-vs],[-hs,-vs],[2*hs,0],[-2*hs,0],[0,2*vs],[0,-2*vs]];
    const radial = offsets.map(([x,y]) => ({ x: preferred.x + x, y: preferred.y + y }));
    const minX = frame.x + EDGE_INSET + width / 2, maxX = frame.x + frame.width - EDGE_INSET - width / 2;
    const minY = frame.y + EDGE_INSET + height / 2, maxY = frame.y + frame.height - EDGE_INSET - height / 2;
    let xs = [minX, maxX, (minX + maxX) / 2];
    if (width * 3 + SPACING * 2 <= frame.width - 16) xs = [...xs, minX + (maxX-minX)/3, minX + (maxX-minX)*2/3];
    const rows = Math.max(2, Math.ceil(objectCount / 2), Math.floor((maxY-minY) / (height+SPACING)) + 1);
    const ys = rows <= 1 || minY === maxY ? [(minY+maxY)/2] : Array.from({length: rows}, (_,i) => minY + (maxY-minY)*i/(rows-1));
    const grid = ys.flatMap(y => xs.map(x => ({x,y})));
    const seen = new Set<string>();
    return [...primary, ...radial, ...grid].map(point => makePlacement(object, point, target, width, frame)).filter(candidate => {
        const key = `${Math.round(candidate.labelCenter.x)}:${Math.round(candidate.labelCenter.y)}`;
        if (seen.has(key)) return false; seen.add(key); return true;
    });
}

function searchedPlacements<T extends AnnotationObject>(objects: T[], frame: Box, movableObjectId?: string): Placement<T>[] {
    const movable = objects.find(object => object.id === movableObjectId);
    const ordered = [...(movable ? [movable] : []), ...objects.filter(o => o.id !== movableObjectId && o.labelCenterOverride), ...objects.filter(o => o.id !== movableObjectId && !o.labelCenterOverride)];
    const targets = objects.map(object => targetPoint(object, frame));
    let states: { placements: Placement<T>[]; cost: number }[] = [{ placements: [], cost: 0 }];
    for (const object of ordered) {
        const target = targetPoint(object, frame);
        const candidates = placementCandidates(object, target, frame, objects.length, movableObjectId);
        const preferred = object.labelCenterOverride ? makePlacement(object, { x: frame.x+frame.width*object.labelCenterOverride.x, y: frame.y+frame.height*object.labelCenterOverride.y }, target, wordLabelWidth(object.english, frame, object.labelScale, object.labelScale !== undefined), frame).labelCenter : target;
        const next: typeof states = [];
        for (const state of states) {
            for (let priority=0; priority<candidates.length; priority++) {
                const candidate = candidates[priority], protectedFrame = inset(candidate.labelFrame, -SPACING/2);
                if (state.placements.some(p => intersects(protectedFrame, inset(p.labelFrame, -SPACING/2)))) continue;
                const covered = targets.filter(t => contains(protectedFrame, t)).length;
                const cost = distance(candidate.labelCenter, preferred) + distance(candidate.labelCenter, candidate.target)*.08 + priority*1.5 + covered*(object.labelCenterOverride ? 100 : 100000);
                next.push({ placements: [...state.placements, candidate], cost: state.cost + cost });
            }
            next.push({ placements: state.placements, cost: state.cost + 10000000 });
        }
        states = next.sort((a,b) => b.placements.length-a.placements.length || a.cost-b.cost).slice(0, BEAM_WIDTH);
    }
    const selected = states[0]?.placements ?? [];
    return objects.flatMap(object => selected.filter(p => p.id === object.id));
}

function quadraticSamples(start: Point, control: Point, target: Point): Point[] {
    return Array.from({length:65},(_,step) => { const t=step/64, inv=1-t; return { x:inv*inv*start.x+2*inv*t*control.x+t*t*target.x, y:inv*inv*start.y+2*inv*t*control.y+t*t*target.y }; });
}
function segmentIntersectsBox(start: Point, end: Point, box: Box) {
    if (contains(box,start)||contains(box,end)) return true;
    const dx=end.x-start.x, dy=end.y-start.y; let lower=0, upper=1;
    for (const [direction,distanceToEdge] of [[-dx,start.x-box.x],[dx,box.x+box.width-start.x],[-dy,start.y-box.y],[dy,box.y+box.height-start.y]]) {
        if (Math.abs(direction)<Number.EPSILON) { if (distanceToEdge<0) return false; continue; }
        const ratio=distanceToEdge/direction;
        if (direction<0) lower=Math.max(lower,ratio); else upper=Math.min(upper,ratio);
        if (lower>upper) return false;
    }
    return true;
}
function polylineIntersects(points: Point[], box: Box) { return points.slice(1).some((point,index) => segmentIntersectsBox(points[index],point,box)); }

export function routedLeaderLines<T extends AnnotationObject>(placements: Placement<T>[], frame: Box): Route[] {
    const routes: Route[]=[];
    const ordered=[...placements].sort((a,b)=>distance(b.anchor,b.target)-distance(a.anchor,a.target));
    for (const placement of ordered) {
        let best: Route|undefined, bestCost=Infinity;
        const length=distance(placement.anchor,placement.target), bend=Math.min(18,Math.max(2,length*.08));
        for (const offset of [bend,-bend,bend*1.5,-bend*1.5,bend*2.5,-bend*2.5,bend*4,-bend*4,bend*6,-bend*6]) {
            const dx=placement.target.x-placement.anchor.x, dy=placement.target.y-placement.anchor.y, normalLength=Math.max(1,Math.hypot(dx,dy));
            const midpoint={x:(placement.anchor.x+placement.target.x)/2,y:(placement.anchor.y+placement.target.y)/2};
            const control={x:midpoint.x-dy/normalLength*offset,y:midpoint.y+dx/normalLength*offset};
            const samples=quadraticSamples(placement.anchor,control,placement.target);
            if (placements.some(obstacle=>obstacle.id!==placement.id&&polylineIntersects(samples,inset(obstacle.labelFrame,-2)))) continue;
            let cost=Math.abs(offset)*.15;
            for(const point of samples.slice(1)) if(!contains(inset(frame,3),point)) cost+=20000;
            for(const route of routes) for(const point of samples.slice(3,-2)) if(route.samples.slice(3,-2).some(other=>distance(point,other)<SAFE_DISTANCE)) cost+=2500;
            if(cost<bestCost){bestCost=cost;best={id:placement.id,start:placement.anchor,control,target:placement.target,samples};}
        }
        if(best) routes.push(best);
    }
    return routes;
}

export function annotationLayout<T extends AnnotationObject>(objects: T[], frame: Box, movableObjectId?: string): AnnotationLayout<T> {
    const placements=searchedPlacements(objects,frame,movableObjectId);
    return {placements,routes:routedLeaderLines(placements,frame)};
}

// Cover mode retains every label, including labels which cannot fit safely.
export function completeAnnotationLayout<T extends AnnotationObject>(objects: T[], frame: Box): AnnotationLayout<T> {
    const automatic = searchedPlacements(objects, frame);
    const placements = objects.map(object => {
        const target = targetPoint(object, frame);
        if (!object.labelCenterOverride) {
            const found = automatic.find(p => p.id === object.id);
            if (found) return found;
        }
        const point = object.labelCenterOverride ?? { x: (target.x-frame.x)/frame.width, y: (target.y-frame.y)/frame.height };
        return makePlacement(object, { x: frame.x + point.x*frame.width, y: frame.y + point.y*frame.height }, target,
            object.labelWidthOverride ?? wordLabelWidth(object.english, frame, object.labelScale, true), frame);
    });
    return { placements, routes: routedLeaderLines(placements, frame) };
}
