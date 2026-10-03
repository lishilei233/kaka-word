import { useRef, useState, type PointerEvent } from 'react';
import type { RecognitionBox } from '../lib/recognition';
import { constrainRecognitionBox, recognitionCorners, recognitionStrokeScale, resizeRecognitionBox } from '../lib/recognition';
import type { Rect } from '../lib/film-layout';

export function RecognitionFrame({ box, image, opacity = 1, editing = false, onChange }: { box: RecognitionBox; image: Rect; opacity?: number; editing?: boolean; onChange?: (box: RecognitionBox) => void }) {
    const drag = useRef<{ x: number; y: number; scaleX: number; scaleY: number; box: RecognitionBox; kind: string; latest: RecognitionBox } | undefined>(undefined);
    const [temporary, setTemporary] = useState<RecognitionBox>();
    const shown = temporary ?? box;
    const width = shown.width * image.width, height = shown.height * image.height;
    const scale = recognitionStrokeScale(width, height, image.width / 540);
    const path = recognitionCorners(width, height, image.width / 540);
    function begin(event: PointerEvent<HTMLElement>, kind: string) {
        if (!editing || !onChange) return;
        event.preventDefault(); event.stopPropagation();
        event.currentTarget.setPointerCapture(event.pointerId);
        const bounds = event.currentTarget.closest('[data-recognition-frame]')!.getBoundingClientRect();
        drag.current = { x: event.clientX, y: event.clientY, scaleX: bounds.width / shown.width, scaleY: bounds.height / shown.height, box: shown, kind, latest: shown };
    }
    function move(event: PointerEvent<HTMLElement>) {
        const start = drag.current;
        if (!start) return;
        event.preventDefault(); event.stopPropagation();
        const dx = (event.clientX - start.x) / start.scaleX, dy = (event.clientY - start.y) / start.scaleY;
        start.latest = start.kind === 'move' ? constrainRecognitionBox({ ...start.box, x: start.box.x + dx, y: start.box.y + dy }) : resizeRecognitionBox(start.box, start.kind, dx, dy);
        setTemporary(start.latest);
    }
    function finish(event: PointerEvent<HTMLElement>) {
        if (!drag.current) return;
        event.preventDefault(); event.stopPropagation();
        onChange?.(drag.current.latest); drag.current = undefined; setTemporary(undefined);
    }
    function cancel(event: PointerEvent<HTMLElement>) {
        event.stopPropagation(); drag.current = undefined; setTemporary(undefined);
    }
    return <div data-recognition-frame style={{ position: 'absolute', zIndex: editing ? 8 : 2, left: image.x + shown.x * image.width, top: image.y + shown.y * image.height, width, height, opacity, pointerEvents: editing ? 'auto' : 'none', cursor: editing ? 'move' : undefined, touchAction: 'none' }}
        onClick={event => event.stopPropagation()} onPointerDown={event => begin(event, 'move')} onPointerMove={move} onPointerUp={finish} onPointerCancel={cancel}>
        <svg width={width} height={height} style={{ display: 'block', overflow: 'hidden', pointerEvents: 'none' }}>
            <path d={path} fill="none" stroke="#24211E" strokeWidth={4 * scale} strokeLinecap="round" strokeLinejoin="round" />
            <path d={path} fill="none" stroke="#FFDC62" strokeWidth={2.5 * scale} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        {editing && ['nw', 'ne', 'sw', 'se'].map(corner => <div key={corner} aria-label={`识别框 ${corner} 缩放角`} style={{ position: 'absolute', width: 14, height: 14, borderRadius: '50%', background: 'transparent', border: 'none', left: corner.includes('w') ? 0 : width, top: corner.includes('n') ? 0 : height, transform: 'translate(-50%, -50%)', cursor: `${corner}-resize`, touchAction: 'none' }} onPointerDown={event => begin(event, corner)} />)}
    </div>;
}
