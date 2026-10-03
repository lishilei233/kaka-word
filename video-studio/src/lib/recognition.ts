import type { Word } from './project';
export type RecognitionBox = { x: number; y: number; width: number; height: number };
export const RECOGNITION_FRAMES = 6;
export const RECOGNITION_GROW_FRAMES = 8;
const clamp = (v: number, min: number, max: number) => Math.min(max, Math.max(min, v));
export function constrainRecognitionBox(box: RecognitionBox): RecognitionBox {
    const width = clamp(box.width, .02, 1), height = clamp(box.height, .02, 1);
    return { x: clamp(box.x, 0, 1 - width), y: clamp(box.y, 0, 1 - height), width, height };
}
export function recognitionBox(word: Word) {
    if ((word.kind ?? 'object') !== 'object' || !word.box || word.needsLocation) return undefined;
    return constrainRecognitionBox(word.recognitionBoxOverride ?? word.box);
}
export function resizeRecognitionBox(box: RecognitionBox, corner: string, dx: number, dy: number) {
    const right = box.x + box.width, bottom = box.y + box.height;
    const x = corner.includes('w') ? clamp(box.x + dx, 0, right - .02) : box.x;
    const y = corner.includes('n') ? clamp(box.y + dy, 0, bottom - .02) : box.y;
    return { x, y, width: corner.includes('w') ? right - x : clamp(right + dx, x + .02, 1) - x,
        height: corner.includes('n') ? bottom - y : clamp(bottom + dy, y + .02, 1) - y };
}
export function recognitionAnimation(frame: number, from: number) {
    const elapsed = frame - from;
    const progress = clamp((elapsed - RECOGNITION_FRAMES) / RECOGNITION_GROW_FRAMES, 0, 1);
    return { cornersVisible: elapsed >= 0 && elapsed < RECOGNITION_FRAMES,
        cornerOpacity: elapsed < 0 ? 0 : Math.min(1, (elapsed + 1) / 2),
        focusProgress: 1 - Math.pow(1 - clamp(elapsed / (RECOGNITION_FRAMES - 1), 0, 1), 3),
        progress: 1 - Math.pow(1 - progress, 3) };
}
export function recognitionStrokeScale(width: number, height: number, scale = 1) {
    return Math.min(scale, Math.min(width, height) / 16);
}
export function recognitionCorners(width: number, height: number, scale = 1) {
    scale = recognitionStrokeScale(width, height, scale);
    const inset = 2 * scale;
    const length = Math.min(18 * scale, (width - 2 * inset) * .25, (height - 2 * inset) * .25);
    const radius = Math.min(3 * scale, length / 2);
    return [[inset, inset, 1, 1], [width - inset, inset, -1, 1],
        [inset, height - inset, 1, -1], [width - inset, height - inset, -1, -1]]
        .map(([x, y, h, v]) => `M ${x + h * length} ${y} L ${x + h * radius} ${y} Q ${x} ${y} ${x} ${y + v * radius} L ${x} ${y + v * length}`).join(' ');
}

/** Expand the corners outward, then settle on the saved object range. */
export function recognitionFocusBox(box: RecognitionBox, progress: number): RecognitionBox {
    const remaining = 1 - clamp(progress, 0, 1);
    const paddingX = Math.min(.025, box.width * .18) * remaining;
    const paddingY = Math.min(.025, box.height * .18) * remaining;
    const x = Math.max(0, box.x - paddingX), y = Math.max(0, box.y - paddingY);
    return { x, y, width: Math.min(1, box.x + box.width + paddingX) - x, height: Math.min(1, box.y + box.height + paddingY) - y };
}
