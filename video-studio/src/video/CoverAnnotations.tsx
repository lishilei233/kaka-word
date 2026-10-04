import { annotationLayout, type Box } from '../lib/annotation-layout';
import { annotatedWords, type Project } from '../lib/project';
import { leaderStyle, objectCapsuleStyle } from './annotation-style';

/** Project all photo-space annotations through the cover crop. */
export function CoverAnnotations({ project, photo }: { project: Project; photo: Box }) {
    const words = annotatedWords(project.words).map(word => {
        const settings = project.cover?.words[word.id];
        const target = settings?.targetCenterOverride ?? word.targetCenterOverride ?? { x: word.box.x + word.box.width / 2, y: word.box.y + word.box.height / 2 };
        const x = (photo.x + target.x * photo.width) / 1080, y = (photo.y + target.y * photo.height) / 1440;
        const label = settings?.labelCenterOverride ?? word.labelCenterOverride;
        return { ...word, box: { x, y, width: 0, height: 0 }, targetCenterOverride: { x, y },
            labelCenterOverride: label ? { x: (photo.x + label.x * photo.width) / 1080, y: (photo.y + label.y * photo.height) / 1440 } : undefined };
    });
    const line = leaderStyle(false);
    const layout = annotationLayout(words, { x: 0, y: 0, width: 540, height: 720 });
    if (!words.length) return null;
    return <div aria-label="物体与形容词标注" style={{ position: 'absolute', inset: 0, width: 540, height: 720, transform: 'scale(2)', transformOrigin: 'top left', pointerEvents: 'none' }}>
        <svg width={540} height={720} style={{ position: 'absolute', inset: 0 }} aria-hidden>
            {layout.routes.map(route => {
                const d = `M ${route.start.x} ${route.start.y} Q ${route.control.x} ${route.control.y} ${route.target.x} ${route.target.y}`;
                return <g key={route.id}>
                    <path d={d} fill="none" pathLength={100} stroke={line.ink} strokeWidth={line.outer} strokeDasharray={line.dash} strokeLinecap="round" strokeLinejoin="round" />
                    <path d={d} fill="none" pathLength={100} stroke={line.fill} strokeWidth={line.inner} strokeDasharray={line.dash} strokeLinecap="round" strokeLinejoin="round" />
                    <circle cx={route.target.x} cy={route.target.y} r={line.dotOuter} fill={line.ink} />
                    <circle cx={route.target.x} cy={route.target.y} r={line.dotInner} fill={line.fill} />
                </g>;
            })}
        </svg>
        {layout.placements.map(item => <div key={item.id} style={{ ...objectCapsuleStyle, position: 'absolute', left: item.labelFrame.x, top: item.labelFrame.y,
            width: item.labelWidth, height: item.labelHeight, boxSizing: 'border-box', padding: '0 12px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'clip', textAlign: 'center', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 16, fontWeight: 700 }}>
            {item.object.english}
        </div>)}
    </div>;
}
