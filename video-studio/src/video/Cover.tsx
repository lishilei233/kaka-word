import { Img } from 'remotion';
import { isQuestionCover, questionCoverLayout } from '../lib/cover-layout';
import type { Project } from '../lib/project';
import { LegacyCover, type CoverMove } from './LegacyCover';

export function Cover({ project }: { project: Project; onMove?: CoverMove }) {
    if (!isQuestionCover(project)) return <LegacyCover project={project} />;
    const layout = questionCoverLayout(project);
    const top = layout.position === 'top';
    const textHeight = layout.heading.lines.length * layout.heading.fontSize * 1.18
        + (layout.words.length ? 32 + layout.wordRows.length * (layout.wordFontSize * 1.2 + 26) + Math.max(0, layout.wordRows.length - 1) * 14 : 0);
    const washHeight = Math.max(560, textHeight + 200);
    return <div aria-label="场景问题封面" style={{ position: 'relative', width: 1080, height: 1440, overflow: 'hidden', background: '#f8f3e7', color: '#263e33', fontFamily: "'PingFang SC', Arial, sans-serif" }}>
        {project.image ? <Img src={project.image} style={{ position: 'absolute', left: layout.photo.x, top: layout.photo.y, width: layout.photo.width, height: layout.photo.height, maxWidth: 'none' }} />
            : <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', fontSize: 32 }}>从一张生活照片开始</div>}
        <div aria-hidden style={{ position: 'absolute', left: 0, right: 0, [top ? 'top' : 'bottom']: 0, height: washHeight,
            background: `linear-gradient(${top ? '180deg' : '0deg'}, rgba(255,250,235,.98) 0%, rgba(255,250,235,.94) 48%, rgba(255,250,235,.60) 76%, rgba(255,250,235,0) 100%)` }} />
        <section style={{ position: 'absolute', left: 72, right: 72, [top ? 'top' : 'bottom']: 72 }}>
            <div style={{ fontSize: layout.heading.fontSize, fontWeight: 900, lineHeight: 1.18, letterSpacing: 0 }}>
                {layout.heading.fits ? layout.heading.lines.map((line, index) => <div key={index} style={{ whiteSpace: 'pre', color: index === layout.heading.lines.length - 1 ? '#38634c' : '#263e33' }}>{line}</div>)
                    : <div style={{ fontSize: 56, lineHeight: 1.3 }}>{layout.title ? '请缩短标题后导出' : '请填写标题后导出'}</div>}
            </div>
            {layout.words.length > 0 && <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 14, marginTop: 32 }}>
                {layout.wordRows.map((row, index) => <div key={index} style={{ display: 'flex', gap: 16 }}>{row.words.map(word => <span key={word.id} style={{
                    display: 'inline-flex', alignItems: 'center', borderRadius: 12, padding: '13px 24px', background: '#ffe5a0', color: '#304638',
                    fontFamily: 'Arial, sans-serif', fontWeight: 700, fontSize: layout.wordFontSize, lineHeight: 1.2, whiteSpace: 'nowrap',
                }}>{word.english}</span>)}</div>)}
            </div>}
        </section>
    </div>;
}
