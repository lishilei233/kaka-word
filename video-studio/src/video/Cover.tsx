import { annotationHighlight, leaderStyle } from './annotation-style';
import { SceneCards } from './SceneCards';
import { Img } from 'remotion';
import { useMemo, useRef, type PointerEvent } from 'react';
import { coverLayout } from '../lib/cover-layout';
import type { Project } from '../lib/project';
import type { Point } from '../lib/annotation-layout';

export type CoverMove = (id: string, kind: 'label' | 'target', point: Point) => void;
export function Cover({ project, onMove }: { project: Project; onMove?: CoverMove }) {
    const layout = useMemo(() => coverLayout(project), [project.imageWidth, project.imageHeight, project.words, project.cover]);
    const drag = useRef<{ id: string; kind: 'label' | 'target'; start: Point; origin: Point; point: Point } | null>(null);
    function begin(e: PointerEvent<SVGGElement>, id: string, kind: 'label' | 'target', origin: Point) {
        if (!onMove) return;
        e.preventDefault(); e.stopPropagation(); e.currentTarget.setPointerCapture(e.pointerId);
        drag.current = { id, kind, origin, point: origin, start: { x: e.clientX, y: e.clientY } };
    }
    function move(e: PointerEvent<SVGGElement>) {
        const d = drag.current;
        if (!d) return;
        const bounds = e.currentTarget.ownerSVGElement!.getBoundingClientRect();
        const dx = (e.clientX-d.start.x)*1080/bounds.width, dy = (e.clientY-d.start.y)*1440/bounds.height;
        d.point = { x: d.origin.x+dx, y: d.origin.y+dy };
        e.currentTarget.setAttribute('transform', `translate(${dx} ${dy})`);
    }
    function finish(e: PointerEvent<SVGGElement>, cancel = false) {
        const d = drag.current; drag.current = null;
        e.currentTarget.removeAttribute('transform');
        if (!d || cancel) return;
        const p = layout.photo;
        onMove?.(d.id, d.kind, { x: Math.max(0, Math.min(1, (d.point.x-p.x)/p.width)), y: Math.max(0, Math.min(1, (d.point.y-p.y)/p.height)) });
    }
    const p = layout.photo;
    return <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1080 1440" style={{ width: '100%', height: '100%', display: 'block', background: '#f6f0e4', touchAction: 'none', overflow: 'hidden' }} aria-label="学习卡片封面">
        {project.image ? <foreignObject x={p.x} y={p.y} width={p.width} height={p.height}><Img src={project.image} style={{ width: '100%', height: '100%', objectFit: 'contain' }} /></foreignObject> : <text x="540" y="720" textAnchor="middle" fill="#a69884" fontSize="32">从一张生活照片开始</text>}
        {layout.routes.map(r => { const line = leaderStyle(!!project.cover?.words[r.id]?.highlighted, 2); return <g key={r.id} pointerEvents="none" style={{ filter: line.filter }}>
            <path d={`M${r.start.x} ${r.start.y} Q${r.control.x} ${r.control.y} ${r.target.x} ${r.target.y}`} fill="none" stroke={line.ink} strokeWidth={line.outer} strokeDasharray={line.dash} strokeLinecap="round" />
            <path d={`M${r.start.x} ${r.start.y} Q${r.control.x} ${r.control.y} ${r.target.x} ${r.target.y}`} fill="none" stroke={line.fill} strokeWidth={line.inner} strokeDasharray={line.dash} strokeLinecap="round" />
        </g>; })}
        {layout.placements.map(item => { const highlighted = !!project.cover?.words[item.id]?.highlighted; const line = leaderStyle(highlighted, 2); return <g key={item.id}>
            <g style={{ cursor: onMove ? 'grab' : undefined }} onPointerDown={e => begin(e, item.id, 'target', item.target)} onPointerMove={move} onPointerUp={e => finish(e)} onPointerCancel={e => finish(e, true)}>
                <circle cx={item.target.x} cy={item.target.y} r="22" fill="transparent" /><circle cx={item.target.x} cy={item.target.y} r={line.dotOuter} fill={line.ink} style={{ filter: line.filter }} /><circle cx={item.target.x} cy={item.target.y} r={line.dotInner} fill={line.fill} />
            </g>
            <g style={{ cursor: onMove ? 'grab' : undefined }} onPointerDown={e => begin(e, item.id, 'label', item.labelCenter)} onPointerMove={move} onPointerUp={e => finish(e)} onPointerCancel={e => finish(e, true)}>
                {highlighted && <rect x={item.labelFrame.x-4} y={item.labelFrame.y-4} width={item.labelWidth+8} height={item.labelHeight+8} rx={item.labelHeight/2+4} fill={annotationHighlight.ring} style={{ filter: 'drop-shadow(0 8px 12px rgba(36,33,30,.28))' }} />}
                <rect {...{ x: item.labelFrame.x, y: item.labelFrame.y, width: item.labelWidth, height: item.labelHeight }} rx={item.labelHeight/2} fill={highlighted ? annotationHighlight.fill : '#f4c95d'} stroke={onMove && layout.conflicts.includes(item.id) ? '#c43f35' : '#24211e'} strokeOpacity={onMove && layout.conflicts.includes(item.id) ? 1 : highlighted ? .88 : .18} strokeWidth={highlighted ? 4 : 3} />
                <text x={item.labelCenter.x} y={item.labelCenter.y} dominantBaseline="central" textAnchor="middle" fill={'#24211e'} fontFamily="'SF Pro Rounded', ui-rounded, system-ui, sans-serif" fontWeight="900" fontSize={16*item.object.labelScale}>{item.object.english}</text>
            </g>
        </g>; })}
        {layout.sceneHeight > 0 && <foreignObject x={layout.sceneLeft} y={layout.sceneTop} width={layout.sceneWidth} height={layout.sceneHeight} style={{ overflow: 'visible' }}><div style={{ width: layout.sceneWidth/2, transform: 'scale(2)', transformOrigin: 'top left' }}><SceneCards project={project} cover width={layout.sceneWidth/2} /></div></foreignObject>}
    </svg>;
}
