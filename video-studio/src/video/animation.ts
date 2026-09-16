import { interpolate } from 'remotion';

export const ANIMATION = {
    labelIn: 8,
    highlight: 10,
    detailIn: 8,
    detailOut: 4,
    descriptionIn: 12,
    chineseDelay: 4,
    lineIn: 8,
} as const;

const easeOut = (value: number) => 1 - Math.pow(1 - Math.max(0, Math.min(1, value)), 3);
export function progress(frame: number, from: number, duration: number) {
    return easeOut((frame - from) / Math.max(1, duration));
}
export function labelEntrance(frame: number, from: number) {
    const value = progress(frame, from, ANIMATION.labelIn);
    return { opacity: value, translateY: (1 - value) * 6 };
}
export function highlightScale(frame: number, from: number) {
    const elapsed = Math.max(0, frame - from);
    if (elapsed >= ANIMATION.highlight) return 1.2;
    return interpolate(elapsed, [0, 5, ANIMATION.highlight], [1, 1.24, 1.2], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
}
export function sceneHighlightScale(frame: number, from: number) {
    const elapsed = Math.max(0, frame - from);
    if (elapsed >= ANIMATION.highlight) return 1.04;
    return interpolate(elapsed, [0, 5, ANIMATION.highlight], [1, 1.08, 1.04], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
}
export function detailEntrance(frame: number, from: number) {
    const value = progress(frame, from, ANIMATION.detailIn);
    return { opacity: value, translateY: (1 - value) * 8 };
}
export function descriptionEntrance(frame: number, from: number) {
    const value = progress(frame, from, ANIMATION.descriptionIn);
    return { opacity: value, translateY: (1 - value) * 10, chineseOpacity: progress(frame, from + ANIMATION.chineseDelay, ANIMATION.descriptionIn - ANIMATION.chineseDelay) };
}
export function lineEntrance(frame: number, from: number) {
    return progress(frame, from, ANIMATION.lineIn);
}
