import { SceneCards } from './SceneCards';
import { CoverAnnotations } from './CoverAnnotations';
import { Img } from 'remotion';
import { isQuestionCover, questionCoverLayout } from '../lib/cover-layout';
import { bottomVerbs, type Project } from '../lib/project';
import { LegacyCover, type CoverMove } from './LegacyCover';

export function Cover({ project }: { project: Project; onMove?: CoverMove }) {
    if (!isQuestionCover(project)) return <LegacyCover project={project} />;
    const layout = questionCoverLayout(project);
    const top = layout.position === 'top';
    return <div aria-label="场景问题封面" style={{ position: 'relative', width: 1080, height: 1440, overflow: 'hidden', background: '#24231f', color: '#fff9e9', fontFamily: "'PingFang SC', Arial, sans-serif" }}>
        {project.image ? <Img src={project.image} style={{ position: 'absolute', left: layout.photo.x, top: layout.photo.y, width: layout.photo.width, height: layout.photo.height, maxWidth: 'none' }} />
            : <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', fontSize: 32 }}>从一张生活照片开始</div>}
        <CoverAnnotations project={project} photo={layout.photo} />
        <div aria-hidden style={{ position: 'absolute', left: 0, right: 0, [top ? 'top' : 'bottom']: 0, height: 750,
            background: `linear-gradient(${top ? '180deg' : '0deg'}, rgba(12,17,17,.88) 0%, rgba(12,17,17,.66) 42%, rgba(12,17,17,.2) 76%, transparent 100%)` }} />
        <section style={{ position: 'absolute', left: 72, right: 72, [top ? 'top' : 'bottom']: !top && bottomVerbs(project.words, project.caption).length ? 160 : 72 }}>
            <div style={{ fontSize: layout.heading.fontSize, fontWeight: 900, lineHeight: 1.18, letterSpacing: 0, textShadow: '0 3px 18px rgba(0,0,0,.25)' }}>
                {layout.heading.fits ? layout.heading.lines.map((line, index) => <div key={index} style={{ whiteSpace: 'pre', color: index === layout.heading.lines.length - 1 ? '#ffda63' : '#fff9e9' }}>{line}</div>)
                    : <div style={{ fontSize: 56, lineHeight: 1.3 }}>{layout.title ? '请缩短场景名后导出' : '请填写场景名后导出'}</div>}
            </div>

        </section>
        <div style={{ position: 'absolute', left: 44, bottom: 40, width: 496, transform: 'scale(2)', transformOrigin: 'bottom left' }}>
            <SceneCards project={project} cover />
        </div>
    </div>;
}
