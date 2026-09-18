import { Img } from 'remotion';
import { useMemo } from 'react';
import { coverLayout, defaultCover } from '../lib/cover-layout';
import { annotationHighlight, objectCapsuleStyle, sceneCapsuleHighlight, sceneCapsuleStyle } from './annotation-style';
import type { Project } from '../lib/project';
import type { Point } from '../lib/annotation-layout';

export type CoverMove = (id: string, kind: 'label' | 'target', point: Point) => void;

export function Cover({ project }: { project: Project; onMove?: CoverMove }) {
    const layout = useMemo(
        () => coverLayout(project),
        [project.imageWidth, project.imageHeight, project.words, project.sceneTheme, project.title],
    );
    const cover = project.cover ?? defaultCover;
    const globalScale = Math.max(.72, Math.min(1.15, cover.scale));
    const sceneFontSize = Math.max(20, Math.min(32, 33 - Math.max(0, layout.scenes.length - 4) * 1.5));
    const sceneTitleFontSize = layout.title.length <= 10 ? 64 : layout.title.length <= 16 ? 52 : 42;

    return <div aria-label="学习卡片封面" style={{
        position: 'relative', width: 1080, height: 1440, overflow: 'hidden',
        background: '#302b25', color: '#fff', fontFamily: "'PingFang SC', 'SF Pro Rounded', system-ui, sans-serif",
    }}>
        {project.image
            ? <Img src={project.image} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
            : <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', color: '#a69884', background: '#f6f0e4', fontSize: 32 }}>从一张生活照片开始</div>}

        <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(180deg, rgba(82,55,31,.26) 0%, rgba(82,55,31,.06) 28%, transparent 48%, rgba(82,55,31,.08) 62%, rgba(66,43,24,.58) 100%)' }} />

        <header style={{
            position: 'absolute', top: 62, left: 54, width: 950, boxSizing: 'border-box',
            padding: '38px 44px 34px', transform: 'rotate(-.7deg)', transformOrigin: 'center',
            background: 'repeating-linear-gradient(0deg, rgba(119,153,171,.1) 0, rgba(119,153,171,.1) 2px, transparent 2px, transparent 39px), rgba(255,249,232,.96)',
            border: '2px solid rgba(80,59,38,.2)', borderRadius: 18, color: '#2f2923',
            boxShadow: '10px 13px 0 rgba(244,201,93,.3), 0 14px 28px rgba(55,36,20,.2)',
        }}>
            <div aria-hidden style={{ position: 'absolute', top: -17, left: 385, width: 168, height: 34, transform: 'rotate(2deg)', background: 'rgba(244,201,93,.72)', borderLeft: '2px dashed rgba(119,90,37,.2)', borderRight: '2px dashed rgba(119,90,37,.2)' }} />
            <div style={{ display: 'flex', alignItems: 'center', gap: 15, marginBottom: 17, fontFamily: 'Menlo, ui-monospace, monospace', fontSize: 17, fontWeight: 900, letterSpacing: 3.2, lineHeight: 1 }}>
                <span style={{ color: '#c96855' }}>KAKA WORD · 实景英语</span>
                <span style={{ flex: 1, height: 2, background: 'rgba(73,61,48,.2)' }} />
                <span style={{ color: '#766a5c' }}>LESSON {String(layout.wordCount).padStart(2, '0')}</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, fontFamily: "'Hiragino Maru Gothic ProN', 'PingFang SC', sans-serif", fontWeight: 900, letterSpacing: -2, lineHeight: 1.08 }}>
                <span style={{ fontSize: 38 }}>在真实场景里</span>
                <span style={{ position: 'relative', zIndex: 0, whiteSpace: 'nowrap', fontSize: 50 }}>
                    <span aria-hidden style={{ position: 'absolute', zIndex: -1, left: -6, right: -7, bottom: 2, height: 21, transform: 'rotate(-1.5deg)', borderRadius: 4, background: '#ffdc62' }} />
                    学英语
                </span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 13, marginTop: 15, fontFamily: "'Hiragino Maru Gothic ProN', 'PingFang SC', sans-serif", color: '#2f2923', fontSize: sceneTitleFontSize, fontWeight: 900, letterSpacing: -2.5, lineHeight: 1.1 }}>
                <span style={{ flex: '0 0 auto', color: '#c96855', fontSize: 30 }}>✦</span>
                <span style={{ minWidth: 0 }}>本期 · {layout.title}</span>
            </div>
        </header>

        <section style={{ position: 'absolute', left: 54, right: 54, bottom: 50, display: 'flex', flexDirection: 'column', alignItems: 'stretch', gap: 16 }}>
            <div style={{ width: '100%', display: 'flex', flexWrap: 'wrap', justifyContent: 'center', gap: '15px 14px' }}>
                {layout.objects.map(word => {
                    const settings = cover.words[word.id];
                    const highlighted = !!settings?.highlighted;
                    const itemScale = Math.max(.85, Math.min(1.2, settings?.scale ?? 1));
                    return <div key={word.id} style={{
                        ...objectCapsuleStyle,
                        boxSizing: 'border-box', minHeight: 58 * globalScale * itemScale,
                        padding: `${11 * globalScale * itemScale}px ${26 * globalScale * itemScale}px`,
                        border: highlighted ? `3px solid ${annotationHighlight.ink}` : objectCapsuleStyle.border,
                        background: highlighted ? annotationHighlight.fill : objectCapsuleStyle.background,
                        fontWeight: highlighted ? 800 : 700,
                        boxShadow: highlighted ? `0 0 0 4px ${annotationHighlight.ring}, ${annotationHighlight.shadow}` : '0 5px 12px rgba(36,33,30,.2)',
                        fontSize: 36 * globalScale * itemScale, whiteSpace: 'nowrap',
                    }}>{word.english}</div>;
                })}
            </div>

            {layout.scenes.length > 0 && <div style={{
                display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 10,
                width: '100%', maxWidth: '100%', overflow: 'hidden', whiteSpace: 'nowrap',
            }}>
                {layout.scenes.map(word => {
                    const highlighted = !!cover.words[word.id]?.highlighted;
                    return <span key={word.id} style={{
                        ...sceneCapsuleStyle, minWidth: 0, flex: '0 1 auto',
                        padding: '11px 22px', overflow: 'hidden', textOverflow: 'ellipsis',
                        border: highlighted ? `3px solid ${sceneCapsuleHighlight.ink}` : sceneCapsuleStyle.border,
                        background: highlighted ? sceneCapsuleHighlight.fill : sceneCapsuleStyle.background,
                        fontWeight: highlighted ? 800 : 700,
                        boxShadow: highlighted ? `0 0 0 4px ${sceneCapsuleHighlight.ring}, ${sceneCapsuleHighlight.shadow}` : '0 5px 12px rgba(36,73,82,.2)',
                        fontSize: sceneFontSize,
                    }}>{word.english}</span>;
                })}
            </div>}
        </section>
    </div>;
}
