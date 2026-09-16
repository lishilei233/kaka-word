export const annotationHighlight = {
    scale: 1.08,
    fill: '#ffdc62',
    ink: 'rgba(36,33,30,.88)',
    ring: 'rgba(255,255,255,.72)',
    border: 2,
    ringSize: 2,
    shadow: '0 5px 12px rgba(36,33,30,.28)',
};
export function leaderStyle(highlighted: boolean, scale = 1) {
    return {
        outer: (highlighted ? 6 : 5) * scale,
        inner: (highlighted ? 3 : 2) * scale,
        dotOuter: (highlighted ? 6 : 5) * scale,
        dotInner: (highlighted ? 3.5 : 3) * scale,
        fill: highlighted ? annotationHighlight.fill : '#f4c95d',
        ink: highlighted ? annotationHighlight.ink : 'rgba(36,33,30,.78)',
        dash: highlighted ? undefined : `${5*scale} ${4*scale}`,
        filter: highlighted ? `drop-shadow(0 ${1*scale}px ${2*scale}px rgba(36,33,30,.24))` : undefined,
    };
}
