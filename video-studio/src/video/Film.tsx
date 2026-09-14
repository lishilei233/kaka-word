import { AbsoluteFill, Audio, Freeze, Img, OffthreadVideo, Sequence, interpolate, staticFile, useCurrentFrame } from 'remotion';
import { activeWord, AUDIO_LEAD_FRAMES, AUDIO_TAIL_FRAMES, FPS, openingMedia, timeline, type Project } from '../lib/project';
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

export function Film({ project: p, onAnnotationMove, onAnnotationDragStart }: { project: Project; onAnnotationMove?: AnnotationMove; onAnnotationDragStart?: () => void }) {
    const frame = useCurrentFrame();
    const t = timeline(p), current = activeWord(p, frame), opening = frame < t.intro;
    const layout = filmLayout(p);
    const photo = opening ? layout.camera : layout.photo;
    const image = opening ? layout.cameraImage : layout.photoImage;
    const mediaStyle: CSSProperties = { ...rectStyle({ ...image, x: image.x - photo.x, y: image.y - photo.y }), objectFit: 'contain' };
    const captureFrame = Math.round(p.captureSeconds * FPS);
    const { holdFrames, startFrom } = openingMedia(p);
    const wordIndex = current ? p.words.findIndex(w => w.id === current.id) : -1;
    const shutterScale = interpolate(frame, [Math.max(0, t.intro - 7), Math.max(0, t.intro - 3), t.intro], [1, .84, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
    const textWidth = layout.textRight - layout.textLeft;
    const annotations = useMemo(
        () => annotationLayout(p.words, layout.photoImage),
        [p.words, layout.photoImage.x, layout.photoImage.y, layout.photoImage.width, layout.photoImage.height],
    );
    const drag = useRef<{ id: string; kind: 'label' | 'target'; point: { x: number; y: number } } | undefined>(undefined);
    function dragPoint(event: ReactPointerEvent<Element>, id: string, kind: 'label' | 'target') {
        if (!onAnnotationMove || event.buttons !== 1) return;
        const media = event.currentTarget.closest('[data-film-media]');
        if (!media) return;
        const bounds = media.getBoundingClientRect();
        const point = {
            x: Math.min(1, Math.max(0, (event.clientX - bounds.left) / bounds.width)),
            y: Math.min(1, Math.max(0, (event.clientY - bounds.top) / bounds.height)),
        };
        drag.current = { id, kind, point };
        if (kind === 'label') {
            const element = event.currentTarget as HTMLElement;
            element.style.left = `${point.x * photo.width}px`;
            element.style.top = `${point.y * photo.height}px`;
        } else {
            const group = event.currentTarget.parentElement;
            group?.querySelectorAll('circle').forEach(circle => {
                circle.setAttribute('cx', String(point.x * photo.width));
                circle.setAttribute('cy', String(point.y * photo.height));
            });
        }
    }
    function beginDrag(event: ReactPointerEvent<Element>, id: string, kind: 'label' | 'target') {
        if (!onAnnotationMove) return;
        event.preventDefault(); event.stopPropagation();
        event.currentTarget.setPointerCapture(event.pointerId);
        onAnnotationDragStart?.();
        const word = p.words.find(item => item.id === id);
        drag.current = { id, kind, point: kind === 'label'
            ? word?.labelCenterOverride ?? { x: .5, y: .5 }
            : word?.targetCenterOverride ?? (word ? { x: word.box.x + word.box.width / 2, y: word.box.y + word.box.height / 2 } : { x: .5, y: .5 }) };
    }
    function finishDrag(event: ReactPointerEvent<Element>) {
        if (!onAnnotationMove || !drag.current) return;
        event.preventDefault(); event.stopPropagation();
        const finished = drag.current; drag.current = undefined;
        onAnnotationMove(finished.id, finished.kind, finished.point);
    }
    return <AbsoluteFill style={{ background: opening ? '#191919' : paper }}>
        <div style={{ position: 'absolute', width: 540, height: 960, transform: 'scale(2)', transformOrigin: 'top left', color: opening ? '#fff' : ink, fontFamily: round, overflow: 'hidden', backgroundImage: opening ? undefined : 'repeating-linear-gradient(0deg,transparent 0px,transparent 27px,rgba(109,99,88,.055) 27px,rgba(109,99,88,.055) 28px)' }}>
            <div data-film-media={opening ? 'camera' : 'photo'} style={{ ...rectStyle(photo), overflow: 'hidden', borderRadius: opening ? 0 : 18, background: opening ? '#292929' : '#e9dec9', boxShadow: opening ? undefined : 'inset 0 0 0 4px #fffdf8, 0 3px 0 #24211e24' }}>
                {p.image && <Img src={p.image} style={mediaStyle} />}
                {!p.image && <div style={{ ...center, height: '100%', color: '#a69884', flexDirection: 'column', gap: 16 }}><span style={{ fontSize: 54 }}>＋</span><span style={{ fontSize: 17 }}>从一张生活照片开始</span></div>}
                {opening && p.video && holdFrames > 0 && <Sequence durationInFrames={Math.min(holdFrames, t.intro)} layout="none"><Freeze frame={0}><OffthreadVideo src={p.video} muted style={mediaStyle} /></Freeze></Sequence>}
                {opening && p.video && captureFrame > 0 && <Sequence from={holdFrames} durationInFrames={Math.max(1, t.intro - holdFrames)} layout="none"><OffthreadVideo src={p.video} startFrom={startFrom} muted style={mediaStyle} /></Sequence>}
                {opening && <svg viewBox={`0 0 ${photo.width} ${photo.height}`} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }}><path d={`M50 20H16V54 M${photo.width-50} 20H${photo.width-16}V54 M16 ${photo.height-54}V${photo.height-20}H50 M${photo.width-50} ${photo.height-20}H${photo.width-16}V${photo.height-54}`} stroke="#ffffffbd" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" fill="none" /></svg>}
                {!opening && <>
                    <svg viewBox={`0 0 ${photo.width} ${photo.height}`} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }}>{annotations.routes.map(route => {
                        const segment=t.words.find(item=>item.word.id===route.id), visible=!!segment && frame >= segment.from;
                        const d=`M ${route.start.x-photo.x} ${route.start.y-photo.y} Q ${route.control.x-photo.x} ${route.control.y-photo.y} ${route.target.x-photo.x} ${route.target.y-photo.y}`;
                        return <g key={route.id} opacity={visible?1:0}>
                            <path d={d} fill="none" stroke="rgba(36,33,30,.78)" strokeWidth="5" strokeDasharray="5 4" strokeLinecap="round" strokeLinejoin="round" />
                            <path d={d} fill="none" stroke={sun} strokeWidth="2" strokeDasharray="5 4" strokeLinecap="round" strokeLinejoin="round" />
                            <circle cx={route.target.x-photo.x} cy={route.target.y-photo.y} r="11" fill="transparent" style={{ cursor: onAnnotationMove ? 'grab' : undefined, pointerEvents: onAnnotationMove ? 'all' : 'none' }} onClick={event => { event.preventDefault(); event.stopPropagation(); }} onPointerDown={event => beginDrag(event, route.id, 'target')} onPointerMove={event => dragPoint(event, route.id, 'target')} onPointerUp={finishDrag} onPointerCancel={finishDrag} />
                            <circle cx={route.target.x-photo.x} cy={route.target.y-photo.y} r="5" fill="rgba(36,33,30,.82)" style={{ pointerEvents: 'none' }} />
                            <circle cx={route.target.x-photo.x} cy={route.target.y-photo.y} r="3" fill={sun} style={{ pointerEvents: 'none' }} />
                        </g>;
                    })}</svg>
                    {annotations.placements.map(placement => { const segment=t.words.find(item=>item.word.id===placement.id); const isCurrent=current?.id===placement.id; return <div key={placement.id} onClick={event => { event.preventDefault(); event.stopPropagation(); }} onPointerDown={event => beginDrag(event, placement.id, 'label')} onPointerMove={event => dragPoint(event, placement.id, 'label')} onPointerUp={finishDrag} onPointerCancel={finishDrag} title={onAnnotationMove ? '拖动调整胶囊位置' : undefined} style={{ position: 'absolute', left: placement.labelCenter.x-photo.x, top: placement.labelCenter.y-photo.y, width: placement.labelWidth, height: placement.labelHeight, transform: `translate(-50%,-50%) scale(${isCurrent?1.18:1})`, borderRadius: 999, padding: '0 12px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'clip', display: 'flex', alignItems: 'center', justifyContent: 'center', textAlign: 'center', background: isCurrent ? '#ffd84d' : sun, color: ink, border: isCurrent ? '3px solid rgba(36,33,30,.96)' : '1px solid rgba(36,33,30,.18)', fontFamily: '"SF Pro Rounded", ui-rounded, system-ui, sans-serif', fontWeight: 900, fontSize: 16, lineHeight: 1, boxShadow: isCurrent?'0 0 0 4px rgba(255,255,255,.88), 0 7px 14px rgba(36,33,30,.38)':'none', opacity: segment && frame >= segment.from ? 1 : 0, transition: 'none', cursor: onAnnotationMove ? 'grab' : undefined, touchAction: 'none' }}>{placement.object.english}</div>})}
                    <div style={{ position: 'absolute', inset: 0, borderRadius: 18, boxShadow: 'inset 0 0 0 4px #fffdf8', pointerEvents: 'none' }} />
                </>}
            </div>
            {!opening && frame >= t.captionFrom && <>
                <div style={{ position: 'absolute', left: photo.x + photo.width - 102, top: photo.y - 12, width: 72, height: 18, background: '#f4c95dc7', transform: 'rotate(-4deg)' }} />
                <div data-film-description style={{ position: 'absolute', top: layout.descriptionTop, left: layout.textLeft, width: textWidth, minHeight: 140, padding: 17, boxSizing: 'border-box', overflow: 'hidden', background: 'rgba(255,253,248,.94)', borderRadius: 22, border: '1px solid rgba(36,33,30,.08)', boxShadow: '2px 3px 0 rgba(36,33,30,.1)' }}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 }}><span style={{ fontFamily: mono, fontSize: 10, fontWeight: 900, letterSpacing: 1.6, color: '#d2765f' }}>❝PHOTO NOTE</span></div>
                    <div style={{ ...twoLines, fontFamily: serif, fontSize: p.caption.length > 120 ? 17 : 20, lineHeight: 1.25, fontWeight: 700, color: 'rgba(36,33,30,.86)' }}>{p.caption}</div>
                    <div style={{ ...twoLines, marginTop: p.caption && p.captionChinese ? 8 : 0, fontSize: p.captionChinese.length > 60 ? 14 : 16, lineHeight: 1.35, fontWeight: 600, color: 'rgba(36,33,30,.56)' }}>{p.captionChinese}</div>
                    <div style={{ position: 'absolute', top: -7, left: '42%', width: 82, height: 16, background: 'rgba(143,196,217,.55)', transform: 'rotate(-2deg)' }} />
                </div>
            </>}
            <div style={{ position: 'absolute', top: opening ? layout.shutterTop : frame >= t.captionFrom ? layout.closingTop : layout.wordTop, left: layout.textLeft, width: textWidth, textAlign: 'center', height: opening ? 104 : 92, overflow: 'hidden' }}>
                {opening ? <><div style={center}><div style={{ width: 64, height: 64, borderRadius: '50%', background: sun, border: '5px solid #ffffffe6', boxShadow: shutterScale < .95 ? '0 2px 5px #0005, 0 0 0 8px #f4c95d38' : '0 6px 12px #0004', transform: `scale(${shutterScale})` }} /></div><div style={{ fontSize: 14, marginTop: 14 }}>随手一拍，发现身边的英语</div></> : current ? <>
                    <div style={{ ...twoLines, fontFamily: serif, fontSize: current.english.length > 22 ? 22 : 34, fontWeight: 700, lineHeight: 1.05 }}>{current.english}</div>
                    <div style={{ fontSize: 16, lineHeight: 1.2, marginTop: 7, color: '#6d6358', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{current.ipa} <span style={{ marginLeft: 10 }}>{current.chinese}</span></div>
                    <div style={{ fontFamily: mono, fontSize: 10, marginTop: 9, letterSpacing: 2 }}>{String(wordIndex + 1).padStart(2, '0')} / {String(p.words.length).padStart(2, '0')} · 跟我读</div>
                </> : <></>}
            </div>
            {frame >= t.intro && frame < t.intro + 5 && <div style={{ position: 'absolute', inset: 0, background: 'white', opacity: (5-(frame-t.intro))/5 }} />}
        </div>
        <Sequence from={Math.max(0, t.intro - 3)} durationInFrames={45}><Audio src={staticFile('camera-shutter.mp3')} volume={0.72} pauseWhenBuffering /></Sequence>
        {t.words.map(({ word, from, audioFrames }) => word.audio ? <Sequence key={word.id} from={from + AUDIO_LEAD_FRAMES} durationInFrames={audioFrames + AUDIO_TAIL_FRAMES}><Audio src={word.audio} pauseWhenBuffering /></Sequence> : null)}
        {p.captionAudio && <Sequence from={t.captionFrom + AUDIO_LEAD_FRAMES} durationInFrames={t.captionAudioFrames + AUDIO_TAIL_FRAMES}><Audio src={p.captionAudio} pauseWhenBuffering /></Sequence>}
    </AbsoluteFill>;
}
