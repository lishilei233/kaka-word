export const annotationHighlight = {
    scale: 1.18,
    fill: '#ffd84d',
    ink: 'rgba(36,33,30,.96)',
    ring: 'rgba(255,255,255,.88)',
};
export function leaderStyle(highlighted: boolean, scale = 1) {
    return {
        outer: (highlighted ? 7 : 5) * scale,
        inner: (highlighted ? 3 : 2) * scale,
        dotOuter: (highlighted ? 7 : 5) * scale,
        dotInner: (highlighted ? 4 : 3) * scale,
        fill: highlighted ? annotationHighlight.fill : '#f4c95d',
        ink: highlighted ? annotationHighlight.ink : 'rgba(36,33,30,.78)',
        dash: highlighted ? undefined : `${5*scale} ${4*scale}`,
        filter: highlighted ? `drop-shadow(0 0 ${2*scale}px rgba(255,255,255,.88))` : undefined,
    };
}
