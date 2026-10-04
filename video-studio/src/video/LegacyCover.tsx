import { CoverAnnotations } from './CoverAnnotations';
import { Img } from 'remotion';
import { useMemo } from 'react';
import { coverLayout } from '../lib/cover-layout';
import { SceneCards } from './SceneCards';
import type { Project } from '../lib/project';
import type { Point } from '../lib/annotation-layout';

export type CoverMove = (id: string, kind: 'label' | 'target', point: Point) => void;

export function LegacyCover({ project }: { project: Project; onMove?: CoverMove }) {
    const layout = useMemo(
        () => coverLayout(project),
        [project.imageWidth, project.imageHeight, project.words, project.caption, project.sceneTheme, project.publishingScene],
    );
    const sceneTitleFontSize = layout.heading.fontSize;
    const titleScale = 1.1;

    return <div aria-label="学习卡片封面" style={{
        position: 'relative', width: 1080, height: 1440, overflow: 'hidden',
        background: '#302b25', color: '#fff', fontFamily: "'PingFang SC', 'SF Pro Rounded', system-ui, sans-serif",
    }}>
        {project.image
            ? <Img src={project.image} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
            : <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', color: '#a69884', background: '#f6f0e4', fontSize: 32 }}>从一张生活照片开始</div>}

        <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(180deg, rgba(82,55,31,.26) 0%, rgba(82,55,31,.06) 28%, transparent 48%, rgba(82,55,31,.08) 62%, rgba(66,43,24,.58) 100%)' }} />

        <CoverAnnotations project={project} photo={layout.photo} />

        <header style={{
            position: 'absolute', top: 148, left: 54, width: 950, boxSizing: 'border-box',
            padding: '30px 42px 30px', transform: 'rotate(-.55deg)', transformOrigin: 'center',
            background: 'repeating-linear-gradient(0deg, rgba(119,153,171,.1) 0, rgba(119,153,171,.1) 2px, transparent 2px, transparent 39px), rgba(255,249,232,.985)',
            border: '2px solid rgba(67,48,31,.24)', borderRadius: 18, color: '#241f1a',
            boxShadow: '7px 8px 0 rgba(244,201,93,.26), 0 10px 22px rgba(55,36,20,.18)',
        }}>
            <div aria-hidden style={{ position: 'absolute', top: -17, left: 385, width: 168, height: 34, transform: 'rotate(2deg)', background: 'rgba(244,201,93,.72)', borderLeft: '2px dashed rgba(119,90,37,.2)', borderRight: '2px dashed rgba(119,90,37,.2)' }} />
            <div style={{ display: 'flex', alignItems: 'center', gap: 15, marginBottom: 13, fontFamily: 'Menlo, ui-monospace, monospace', fontSize: 17, fontWeight: 900, letterSpacing: 3.2, lineHeight: 1 }}>
                <span style={{ color: '#c96855' }}>KAKA WORD · 实景英语</span>
                <span style={{ flex: 1, height: 2, background: 'rgba(73,61,48,.2)' }} />
                <span style={{ color: '#766a5c' }}>LESSON {String(layout.wordCount).padStart(2, '0')}</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, fontFamily: "'Hiragino Maru Gothic ProN', 'PingFang SC', sans-serif", fontWeight: 900, letterSpacing: -2.8, lineHeight: 1.04, whiteSpace: 'nowrap' }}>
                <span style={{ fontSize: 56 * titleScale }}>一张照片</span>
                <span style={{ position: 'relative', zIndex: 0, whiteSpace: 'nowrap', fontSize: 72 * titleScale }}>
                    <span aria-hidden style={{ position: 'absolute', zIndex: -1, left: -9, right: -10, bottom: 3, height: 33, transform: 'rotate(-1.5deg)', borderRadius: 5, background: '#ffdc62' }} />
                    学英语
                </span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 12, fontFamily: "'Hiragino Maru Gothic ProN', 'PingFang SC', sans-serif", color: '#3a332c', fontSize: sceneTitleFontSize, fontWeight: 900, letterSpacing: -2.2, lineHeight: 1.1, whiteSpace: 'nowrap' }}>
                <span style={{ flex: '0 0 auto', color: '#c96855', fontSize: 28 }}>✦</span>
                <span style={{ minWidth: 0 }}>{layout.heading.fits ? layout.heading.lines.map((line, index) => <span key={index} style={{ display: 'block', whiteSpace: 'pre' }}>{line}</span>) : '请填写或缩短场景名'}</span>
            </div>
        </header>

        <div style={{ position: 'absolute', left: 44, bottom: 50, width: 496, transform: 'scale(2)', transformOrigin: 'bottom left' }}>
            <SceneCards project={project} cover />
        </div>
    </div>;
}

