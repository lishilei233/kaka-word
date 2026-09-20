import { Img } from 'remotion';
import { useMemo } from 'react';
import { balancedCoverRows, coverLayout, defaultCover } from '../lib/cover-layout';
import { wordLabelWidth } from '../lib/annotation-layout';
import { SCENE_CARD_HEIGHT } from '../lib/film-layout';
import { annotationHighlight, objectCapsuleStyle, sceneCapsuleHighlight, sceneCapsuleStyle } from './annotation-style';
import { sceneCardFontSize, sceneCardWidth } from './SceneCards';
import type { Project } from '../lib/project';
import type { Point } from '../lib/annotation-layout';

export type CoverMove = (id: string, kind: 'label' | 'target', point: Point) => void;

export function Cover({ project }: { project: Project; onMove?: CoverMove }) {
    const layout = useMemo(
        () => coverLayout(project),
        [project.imageWidth, project.imageHeight, project.words, project.sceneTheme, project.title, project.cover?.title],
    );
    const cover = project.cover ?? defaultCover;
    const globalScale = Math.max(.72, Math.min(1.15, cover.scale));
    const sceneTitleFontSize = layout.title.length <= 10 ? 62 : layout.title.length <= 16 ? 56 : 50;
    const titleScale = 1.1;
    // Film renders a 540px logical canvas at 2x for the 1080px output.
    // Keep cover capsules on the same physical metrics as Film/SceneCards.
    const videoOutputScale = 2;
    const capsuleFrame = { x: 0, y: 0, width: 520, height: 720 };
    const objectGap = 14;
    const objectRows = balancedCoverRows(layout.objects.map((word, order) => {
        const itemScale = Math.max(.85, Math.min(1.2, cover.words[word.id]?.scale ?? 1));
        return {
            value: { word, itemScale },
            width: wordLabelWidth(word.english, capsuleFrame, itemScale, false) * videoOutputScale * globalScale,
            order,
        };
    }), 972, objectGap);
    const sceneRowHeight = (SCENE_CARD_HEIGHT + 10) * videoOutputScale * globalScale;

    return <div aria-label="学习卡片封面" style={{
        position: 'relative', width: 1080, height: 1440, overflow: 'hidden',
        background: '#302b25', color: '#fff', fontFamily: "'PingFang SC', 'SF Pro Rounded', system-ui, sans-serif",
    }}>
        {project.image
            ? <Img src={project.image} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
            : <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', color: '#a69884', background: '#f6f0e4', fontSize: 32 }}>从一张生活照片开始</div>}

        <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(180deg, rgba(82,55,31,.26) 0%, rgba(82,55,31,.06) 28%, transparent 48%, rgba(82,55,31,.08) 62%, rgba(66,43,24,.58) 100%)' }} />

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
                <span style={{ fontSize: 56 * titleScale }}>在真实场景里</span>
                <span style={{ position: 'relative', zIndex: 0, whiteSpace: 'nowrap', fontSize: 72 * titleScale }}>
                    <span aria-hidden style={{ position: 'absolute', zIndex: -1, left: -9, right: -10, bottom: 3, height: 33, transform: 'rotate(-1.5deg)', borderRadius: 5, background: '#ffdc62' }} />
                    学英语
                </span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 12, fontFamily: "'Hiragino Maru Gothic ProN', 'PingFang SC', sans-serif", color: '#3a332c', fontSize: sceneTitleFontSize, fontWeight: 900, letterSpacing: -2.2, lineHeight: 1.1, whiteSpace: 'nowrap' }}>
                <span style={{ flex: '0 0 auto', color: '#c96855', fontSize: 28 }}>✦</span>
                <span style={{ minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis' }}>{layout.title}</span>
            </div>
        </header>

        <section style={{ position: 'absolute', left: 54, right: 54, bottom: 50, display: 'flex', flexDirection: 'column', alignItems: 'stretch', gap: 18 }}>
            <div style={{ width: '100%', display: 'flex', flexDirection: 'column', alignItems: 'stretch', gap: 15 }}>
                {objectRows.map((row, rowIndex) => {
                    const rowHeight = Math.max(...row.items.map(item => 42 * videoOutputScale * globalScale * item.value.itemScale));
                    return <div key={`${rowIndex}-${row.items.map(item => item.value.word.id).join('-')}`} style={{
                        width: '100%', height: rowHeight, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: objectGap,
                    }}>
                        {row.items.map(item => {
                            const { word, itemScale } = item.value;
                            const settings = cover.words[word.id];
                            const highlighted = !!settings?.highlighted;
                            const capsuleScale = videoOutputScale * globalScale * itemScale;
                            return <div key={word.id} style={{
                                ...objectCapsuleStyle,
                                boxSizing: 'border-box', width: item.width, height: 42 * capsuleScale,
                                padding: `0 ${12 * capsuleScale}px`,
                                border: highlighted ? `3px solid ${annotationHighlight.ink}` : objectCapsuleStyle.border,
                                background: highlighted ? annotationHighlight.fill : objectCapsuleStyle.background,
                                fontWeight: highlighted ? 800 : 700,
                                boxShadow: highlighted ? `0 0 0 4px ${annotationHighlight.ring}, ${annotationHighlight.shadow}` : 'none',
                                fontSize: 16 * capsuleScale, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'clip',
                                display: 'flex', alignItems: 'center', justifyContent: 'center', textAlign: 'center',
                            }}>{word.english}</div>;
                        })}
                    </div>;
                })}
            </div>

            {layout.scenes.length > 0 && <div style={{
                display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 10,
                width: '100%', height: sceneRowHeight, maxWidth: '100%', overflow: 'hidden', whiteSpace: 'nowrap',
            }}>
                {layout.scenes.map(word => {
                    const highlighted = !!cover.words[word.id]?.highlighted;
                    const capsuleScale = videoOutputScale * globalScale;
                    return <span key={word.id} style={{
                        ...sceneCapsuleStyle, minWidth: 0, flex: '0 1 auto', width: sceneCardWidth(word.english) * capsuleScale,
                        height: (highlighted ? SCENE_CARD_HEIGHT + 10 : SCENE_CARD_HEIGHT) * capsuleScale,
                        padding: `0 ${15 * capsuleScale}px`, overflow: 'hidden', textOverflow: 'ellipsis',
                        border: highlighted ? `3px solid ${sceneCapsuleHighlight.ink}` : sceneCapsuleStyle.border,
                        background: highlighted ? sceneCapsuleHighlight.fill : sceneCapsuleStyle.background,
                        fontWeight: highlighted ? 800 : 700,
                        boxShadow: highlighted ? `0 0 0 3px ${sceneCapsuleHighlight.ring}, ${sceneCapsuleHighlight.shadow}` : 'none',
                        fontSize: sceneCardFontSize(word.english, highlighted) * capsuleScale,
                        display: 'flex', alignItems: 'center', justifyContent: 'center', whiteSpace: 'nowrap',
                    }}>{word.english}</span>;
                })}
            </div>}
        </section>
    </div>;
}
