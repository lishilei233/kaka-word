import { useRef } from 'react';
import type { PointerEvent as ReactPointerEvent } from 'react';
import type { Rect } from '../lib/film-layout';

type Point = { x: number; y: number };

export function interactionArrowGeometry(start: Point, target: Point) {
    const bend = Math.max(34, Math.min(92, Math.abs(target.y - start.y) * .28));
    const control = { x: start.x + (target.x < start.x ? -bend : bend), y: (start.y + target.y) / 2 };
    const angle = Math.atan2(target.y - control.y, target.x - control.x);
    const length = 18, spread = .52;
    const left = { x: target.x - length * Math.cos(angle - spread), y: target.y - length * Math.sin(angle - spread) };
    const right = { x: target.x - length * Math.cos(angle + spread), y: target.y - length * Math.sin(angle + spread) };
    return {
        path: `M ${start.x} ${start.y} Q ${control.x} ${control.y} ${target.x} ${target.y}`,
        head: `${target.x},${target.y} ${left.x},${left.y} ${right.x},${right.y}`,
    };
}

export function InteractionArrow({ photo, descriptionTop, target, progress, onMove, onDragStart }: {
    photo: Rect;
    descriptionTop: number;
    target: Point;
    progress: number;
    onMove?: (point: Point) => void;
    onDragStart?: () => void;
}) {
    const drag = useRef<Point | undefined>(undefined);
    const start = { x: 270, y: Math.min(942, Math.max(photo.y + 24, descriptionTop + 8)) };
    const renderedTarget = { x: photo.x + target.x * photo.width, y: photo.y + target.y * photo.height };
    const geometry = interactionArrowGeometry(start, renderedTarget);
    function pointFromEvent(event: ReactPointerEvent<SVGCircleElement>) {
        const svg = event.currentTarget.ownerSVGElement!;
        const bounds = svg.getBoundingClientRect();
        const logical = { x: (event.clientX - bounds.left) / bounds.width * 540, y: (event.clientY - bounds.top) / bounds.height * 960 };
        return { x: Math.min(.98, Math.max(.02, (logical.x - photo.x) / photo.width)), y: Math.min(.98, Math.max(.02, (logical.y - photo.y) / photo.height)) };
    }
    function move(event: ReactPointerEvent<SVGCircleElement>) {
        if (!onMove || event.buttons !== 1) return;
        const point = pointFromEvent(event); drag.current = point;
        const svg = event.currentTarget.ownerSVGElement!;
        const next = interactionArrowGeometry(start, { x: photo.x + point.x * photo.width, y: photo.y + point.y * photo.height });
        svg.querySelectorAll<SVGPathElement>('[data-interaction-arrow-path]').forEach(path => path.setAttribute('d', next.path));
        svg.querySelector<SVGPolygonElement>('[data-interaction-arrow-head]')?.setAttribute('points', next.head);
        event.currentTarget.setAttribute('cx', String(photo.x + point.x * photo.width));
        event.currentTarget.setAttribute('cy', String(photo.y + point.y * photo.height));
    }
    function finish(event: ReactPointerEvent<SVGCircleElement>) {
        if (!onMove || !drag.current) return;
        event.preventDefault(); event.stopPropagation();
        const point = drag.current; drag.current = undefined; onMove(point);
    }
    return <svg viewBox="0 0 540 960" style={{ position: 'absolute', zIndex: 7, inset: 0, width: '100%', height: '100%', overflow: 'visible', pointerEvents: 'none' }}>
        <path data-interaction-arrow-path d={geometry.path} pathLength={1} fill="none" stroke="rgba(36,33,30,.94)" strokeWidth={9} strokeLinecap="round" style={{ strokeDasharray: 1, strokeDashoffset: 1-progress }} />
        <path data-interaction-arrow-path d={geometry.path} pathLength={1} fill="none" stroke="#ffd84d" strokeWidth={4} strokeLinecap="round" style={{ strokeDasharray: 1, strokeDashoffset: 1-progress }} />
        <polygon data-interaction-arrow-head points={geometry.head} fill="#ffd84d" stroke="rgba(36,33,30,.96)" strokeWidth={4} strokeLinejoin="round" opacity={progress > .72 ? 1 : 0} />
        <circle cx={renderedTarget.x} cy={renderedTarget.y} r={18} fill="transparent" style={{ pointerEvents: onMove ? 'all' : 'none', cursor: onMove ? 'grab' : undefined }} onPointerDown={event => { if (!onMove) return; event.preventDefault(); event.stopPropagation(); event.currentTarget.setPointerCapture(event.pointerId); drag.current = target; onDragStart?.(); }} onPointerMove={move} onPointerUp={finish} onPointerCancel={finish} />
    </svg>;
}
