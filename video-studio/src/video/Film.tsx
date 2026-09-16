import { annotationHighlight, leaderStyle } from './annotation-style';
import { AbsoluteFill, Audio, Freeze, Img, OffthreadVideo, Sequence, interpolate, staticFile, useCurrentFrame } from 'remotion';
import { activeWord, AUDIO_LEAD_FRAMES, AUDIO_TAIL_FRAMES, FPS, openingMedia, timeline, objectWords, readingWords, type Project } from '../lib/project';
import { SceneCards } from './SceneCards';
import { SceneSentence } from './SceneSentence';
import { InteractionArrow } from './InteractionArrow';
import { filmLayout, type Rect } from '../lib/film-layout';
import { annotationLayout } from '../lib/annotation-layout';
import { useMemo, useRef } from 'react';
import type { CSSProperties, PointerEvent as ReactPointerEvent } from 'react';

const ink = '#24211e', paper = '#f6f0e4', sun = '#f4c95d';
const mono = 'Menlo, Consolas, monospace';
const serif = 'Georgia, "Times New Roman", serif';
const round = '"Hiragino Maru Gothic ProN", "PingFang SC", sans-serif';
const center: CSSProperties = { display: 'flex', alignItems: 'center', justifyContent: 'center' };
const twoLines: CSSProperties = { display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' };
function rectStyle(rect: Rect): CSSProperties { return { position: 'absolute', left: rect.x, top: rect.y, width: rect.width, height: rect.height }; }

type AnnotationMove = (id: string, kind: 'label' | 'target', point: { x: number; y: number }) => void;

export function Film({ project: p, renderScale = 1, onAnnotationMove, onInteractionTargetMove, onAnnotationDragStart }: { project: Project; renderScale?: number; onAnnotationMove?: AnnotationMove; onInteractionTargetMove?: (point: { x: number; y: number }) => void; onAnnotationDragStart?: () => void }) {
    const frame = useCurrentFrame();
    const t = timeline(p), current = activeWord(p, frame), direct = p.videoTemplate === 'direct';
    const opening = !direct && frame < t.intro;
    const layout = filmLayout(p);
    const photo = opening ? layout.camera : layout.photo;
    const image = opening ? layout.cameraImage : layout.photoImage;
    const mediaStyle: CSSProperties = { ...rectStyle({ ...image, x: image.x - photo.x, y: image.y - photo.y }), objectFit: 'contain' };
    const captureFrame = Math.round(p.captureSeconds * FPS);
    const { holdFrames, startFrom } = openingMedia(p);
    const wordIndex = current ? t.words.findIndex(item => item.word.id === current.id) : -1;
    const shutterScale = interpolate(frame, [Math.max(0, t.intro - 7), Math.max(0, t.intro - 3), t.intro], [1, .84, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
    const textWidth = layout.textRight - layout.textLeft;
    const annotations = useMemo(
        () => annotationLayout(objectWords(p.words), layout.photoImage),
        [p.words, layout.photoImage.x, layout.photoImage.y, layout.photoImage.width, layout.photoImage.height],
    );
    const drag = useRef<{ id: string; kind: 'label' | 'target'; point: { x: number; y: number } } | undefined>(undefined);
    function dragPoint(event: ReactPointerEvent<Element>, id: string, kind: 'label' | 'target') {
        if (!onAnnotationMove || event.buttons !== 1) return;
        const media = event.currentTarget.closest('[data-film-media]');
        if (!media) return;
        const bounds = media.getBoundingClientRect();
        const scale = bounds.width / photo.width;
        const imageBounds = {
            left: bounds.left + (image.x - photo.x) * scale,
            top: bounds.top + (image.y - photo.y) * scale,
            width: image.width * scale,
            height: image.height * scale,
        };
        const point = {
            x: Math.min(1, Math.max(0, (event.clientX - imageBounds.left) / imageBounds.width)),
            y: Math.min(1, Math.max(0, (event.clientY - imageBounds.top) / imageBounds.height)),
        };
        drag.current = { id, kind, point };
        if (kind === 'label') {
            const element = event.currentTarget as HTMLElement;
            element.style.left = `${image.x - photo.x + point.x * image.width}px`;
            element.style.top = `${image.y - photo.y + point.y * image.height}px`;
        } else {
            const group = event.currentTarget.parentElement;
            group?.querySelectorAll('circle').forEach(circle => {
                circle.setAttribute('cx', String(image.x - photo.x + point.x * image.width));
                circle.setAttribute('cy', String(image.y - photo.y + point.y * image.height));
            });
        }
    }
    function beginDrag(event: ReactPointerEvent<Element>, id: string, kind: 'label' | 'target') {
        if (!onAnnotationMove) return;
        event.preventDefault(); event.stopPropagation();
        event.currentTarget.setPointerCapture(event.pointerId);
        onAnnotationDragStart?.();
        const placement = annotations.placements.find(item => item.id === id);
        const route = annotations.routes.find(item => item.id === id);
        const renderedPoint = kind === 'label' ? placement?.labelCenter : route?.target;
        drag.current = { id, kind, point: renderedPoint ? {
            x: (renderedPoint.x - image.x) / image.width,
            y: (renderedPoint.y - image.y) / image.height,
        } : { x: .5, y: .5 } };
    }
    function finishDrag(event: ReactPointerEvent<Element>) {
        if (!onAnnotationMove || !drag.current) return;
        event.preventDefault(); event.stopPropagation();
        const finished = drag.current; drag.current = undefined;
        onAnnotationMove(finished.id, finished.kind, finished.point);
    }
    return <AbsoluteFill style={{ background: opening ? '#191919' : paper }}>
        <div style={{ position: 'absolute', width: 540, height: 960, transform: `scale(${2 * renderScale})`, transformOrigin: 'top left', color: opening ? '#fff' : ink, fontFamily: round, overflow: 'hidden', backgroundImage: opening ? undefined : 'repeating-linear-gradient(0deg,transparent 0px,transparent 27px,rgba(109,99,88,.055) 27px,rgba(109,99,88,.055) 28px)' }}>
            <div data-film-media={opening ? 'camera' : 'photo'} style={{ ...rectStyle(photo), overflow: 'hidden', borderRadius: opening ? 0 : 18, background: opening ? '#292929' : '#e9dec9', boxShadow: opening ? undefined : 'inset 0 0 0 4px #fffdf8, 0 3px 0 #24211e24' }}>
                {p.image && <Img src={p.image} style={mediaStyle} />}
                {!p.image && <div style={{ ...center, height: '100%', color: '#a69884', flexDirection: 'column', gap: 16 }}><span style={{ fontSize: 54 }}>＋</span><span style={{ fontSize: 17 }}>从一张生活照片开始</span></div>}
                {opening && p.video && holdFrames > 0 && <Sequence durationInFrames={Math.min(holdFrames, t.intro)} layout="none"><Freeze frame={0}><OffthreadVideo src={p.video} muted style={mediaStyle} /></Freeze></Sequence>}
                {opening && p.video && captureFrame > 0 && <Sequence from={holdFrames} durationInFrames={Math.max(1, t.intro - holdFrames)} layout="none"><OffthreadVideo src={p.video} startFrom={startFrom} muted style={mediaStyle} /></Sequence>}
                {opening && <svg viewBox={`0 0 ${photo.width} ${photo.height}`} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }}><path d={`M50 20H16V54 M${photo.width-50} 20H${photo.width-16}V54 M16 ${photo.height-54}V${photo.height-20}H50 M${photo.width-50} ${photo.height-20}H${photo.width-16}V${photo.height-54}`} stroke="#ffffffbd" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" fill="none" /></svg>}
                {!opening && <>
                    <svg viewBox={`0 0 ${photo.width} ${photo.height}`} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }}>{annotations.routes.map(route => {
                        const segment=t.words.find(item=>item.word.id===route.id), visible=direct || (!!segment && frame >= segment.from);
                        const line = leaderStyle(current?.id === route.id);
                        const d=`M ${route.start.x-photo.x} ${route.start.y-photo.y} Q ${route.control.x-photo.x} ${route.control.y-photo.y} ${route.target.x-photo.x} ${route.target.y-photo.y}`;
                        return <g key={route.id} opacity={visible?1:0} style={{ filter: line.filter }}>
                            <path d={d} fill="none" stroke={line.ink} strokeWidth={line.outer} strokeDasharray={line.dash} strokeLinecap="round" strokeLinejoin="round" />
                            <path d={d} fill="none" stroke={line.fill} strokeWidth={line.inner} strokeDasharray={line.dash} strokeLinecap="round" strokeLinejoin="round" />
                            <circle cx={route.target.x-photo.x} cy={route.target.y-photo.y} r="11" fill="transparent" style={{ cursor: onAnnotationMove ? 'grab' : undefined, pointerEvents: onAnnotationMove ? 'all' : 'none' }} onClick={event => { event.preventDefault(); event.stopPropagation(); }} onPointerDown={event => beginDrag(event, route.id, 'target')} onPointerMove={event => dragPoint(event, route.id, 'target')} onPointerUp={finishDrag} onPointerCancel={finishDrag} />
                            <circle cx={route.target.x-photo.x} cy={route.target.y-photo.y} r={line.dotOuter} fill={line.ink} style={{ pointerEvents: 'none' }} />
                            <circle cx={route.target.x-photo.x} cy={route.target.y-photo.y} r={line.dotInner} fill={line.fill} style={{ pointerEvents: 'none' }} />
                        </g>;
                    })}</svg>
                    {annotations.placements.map(placement => { const segment=t.words.find(item=>item.word.id===placement.id); const isCurrent=current?.id===placement.id; return <div key={placement.id} onClick={event => { event.preventDefault(); event.stopPropagation(); }} onPointerDown={event => beginDrag(event, placement.id, 'label')} onPointerMove={event => dragPoint(event, placement.id, 'label')} onPointerUp={finishDrag} onPointerCancel={finishDrag} title={onAnnotationMove ? '拖动调整胶囊位置' : undefined} style={{ position: 'absolute', left: placement.labelCenter.x-photo.x, top: placement.labelCenter.y-photo.y, width: placement.labelWidth, height: placement.labelHeight, transform: `translate(-50%,-50%) scale(${isCurrent?annotationHighlight.scale:1})`, borderRadius: 999, padding: '0 12px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'clip', display: 'flex', alignItems: 'center', justifyContent: 'center', textAlign: 'center', background: isCurrent ? annotationHighlight.fill : sun, color: ink, border: isCurrent ? `${annotationHighlight.border}px solid ${annotationHighlight.ink}` : '1px solid rgba(36,33,30,.18)', fontFamily: '"SF Pro Rounded", ui-rounded, system-ui, sans-serif', fontWeight: 900, fontSize: 16, lineHeight: 1, boxShadow: isCurrent?`0 0 0 ${annotationHighlight.ringSize}px ${annotationHighlight.ring}, ${annotationHighlight.shadow}`:'none', opacity: direct || (segment && frame >= segment.from) ? 1 : 0, transition: 'none', cursor: onAnnotationMove ? 'grab' : undefined, touchAction: 'none' }}>{placement.object.english}</div>})}
                    <div style={{ position: 'absolute', inset: 0, borderRadius: 18, boxShadow: 'inset 0 0 0 4px #fffdf8', pointerEvents: 'none' }} />
                </>}
            </div>
            {!opening && layout.sceneHeight > 0 && <div style={{ position: 'absolute', zIndex: 3, left: layout.sceneLeft, top: layout.sceneTop, width: layout.sceneWidth }}><SceneCards project={p} currentId={current?.id} /></div>}
            {!opening && frame >= t.captionFrom && <>
                <div style={{ position: 'absolute', left: photo.x + photo.width - 102, top: photo.y - 12, width: 72, height: 18, background: '#f4c95dc7', transform: 'rotate(-4deg)' }} />
                    <div data-film-description style={{ position: 'absolute', zIndex: 4, top: layout.descriptionTop, left: layout.textLeft, width: textWidth, minHeight: 140, padding: '12px 14px', boxSizing: 'border-box', overflow: 'hidden', background: 'rgba(255,253,248,.94)', borderRadius: 22, border: '1px solid rgba(36,33,30,.08)', boxShadow: '2px 3px 0 rgba(36,33,30,.1)' }}>
                    <div style={{ position: 'absolute', left: 20, right: 20, top: 0, height: 3, borderRadius: 3, background: 'rgba(210,118,95,.72)' }} />
                    <SceneSentence width={textWidth} english={p.interaction?.enabled && frame >= t.interactionFrom ? p.interaction.english : p.caption} chinese={p.interaction?.enabled && frame >= t.interactionFrom ? p.interaction.chinese : p.captionChinese} vocabulary={p.interaction?.enabled && frame >= t.interactionFrom ? [] : readingWords(p.words).map(word => word.english)} />
                </div>
            </>}
            {!opening && p.interaction?.enabled && p.interaction.arrowEnabled && frame >= t.interactionFrom && <InteractionArrow
                photo={layout.photoImage}
                descriptionTop={layout.descriptionTop}
                target={p.interaction.arrowTarget ?? { x: .5, y: .45 }}
                progress={interpolate(frame-t.interactionFrom, [0, 12], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })}
                onMove={onInteractionTargetMove}
                onDragStart={onAnnotationDragStart}
            />}
            <div style={{ position: 'absolute', zIndex: layout.wordOverPhoto ? 4 : undefined, top: opening ? layout.shutterTop : frame >= t.captionFrom ? layout.closingTop : layout.wordTop, left: layout.textLeft, width: textWidth, textAlign: 'center', height: opening ? 104 : layout.wordDetailHeight, overflow: 'hidden', boxSizing: 'border-box', padding: !opening && layout.wordOverPhoto ? '8px 12px' : undefined, borderRadius: !opening && layout.wordOverPhoto ? 18 : undefined, background: !opening && layout.wordOverPhoto ? 'rgba(255,253,248,.92)' : undefined }}>
                {opening ? <><div style={center}><div style={{ width: 64, height: 64, borderRadius: '50%', background: sun, border: '5px solid #ffffffe6', boxShadow: shutterScale < .95 ? '0 2px 5px #0005, 0 0 0 8px #f4c95d38' : '0 6px 12px #0004', transform: `scale(${shutterScale})` }} /></div><div style={{ fontSize: 14, marginTop: 14 }}>随手一拍，发现身边的英语</div></> : current ? <>
                    <div style={{ ...twoLines, fontFamily: serif, fontSize: current.english.length > 22 ? 22 : 34, fontWeight: 700, lineHeight: 1.05 }}>{current.english}</div>
                    <div style={{ fontSize: 18, lineHeight: 1.25, marginTop: 7, color: '#6d6358', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}><span style={{ fontSize: 14, fontWeight: 800, color: '#8a6540', marginRight: 10 }}>{current.kind === 'action' ? '动作词' : current.kind === 'state' ? '状态词' : '物体词'}</span>{current.ipa} <span style={{ marginLeft: 12 }}>{current.chinese}</span></div>
                    <div style={{ fontFamily: mono, fontSize: 12, marginTop: 10, letterSpacing: 2 }}>{String(wordIndex + 1).padStart(2, '0')} / {String(p.words.length).padStart(2, '0')} · 跟我读</div>
                </> : <></>}
            </div>
            {!direct && frame >= t.intro && frame < t.intro + 5 && <div style={{ position: 'absolute', inset: 0, background: 'white', opacity: (5-(frame-t.intro))/5 }} />}
        </div>
        {!direct && <Sequence from={Math.max(0, t.intro - 3)} durationInFrames={45}><Audio src={staticFile('camera-shutter.mp3')} volume={0.72} pauseWhenBuffering /></Sequence>}
        {t.words.map(({ word, from, audioFrames }) => word.audio ? <Sequence key={word.id} from={from + AUDIO_LEAD_FRAMES} durationInFrames={audioFrames + AUDIO_TAIL_FRAMES}><Audio src={word.audio} pauseWhenBuffering /></Sequence> : null)}
        {p.captionAudio && <Sequence from={t.captionFrom + AUDIO_LEAD_FRAMES} durationInFrames={t.captionAudioFrames + AUDIO_TAIL_FRAMES}><Audio src={p.captionAudio} pauseWhenBuffering /></Sequence>}
        {p.interaction?.enabled && p.interaction.audio && <Sequence from={t.interactionFrom + AUDIO_LEAD_FRAMES} durationInFrames={t.interactionAudioFrames + AUDIO_TAIL_FRAMES}><Audio src={p.interaction.audio} pauseWhenBuffering /></Sequence>}
    </AbsoluteFill>;
}
