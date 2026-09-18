import { sceneWords, type Project } from '../lib/project';
import { timeline } from '../lib/project';
import { SCENE_CARD_HEIGHT } from '../lib/film-layout';
import { annotationHighlight, sceneCapsuleHighlight, sceneCapsuleStyle } from './annotation-style';
import { sceneHighlightScale } from './animation';

function sceneTextWidth(english: string) {
    return [...english].reduce((sum, character) => sum + (/[MW@#%]/.test(character) ? 17 : /[ilI1.,' ]/.test(character) ? 7 : 12), 0);
}
export function sceneCardWidth(english: string) {
    return Math.max(64, Math.min(235, sceneTextWidth(english) + 32));
}
export function sceneCardFontSize(english: string, highlighted: boolean, cardWidth = sceneCardWidth(english)) {
    const preferred = highlighted ? 20 : 16;
    const available = cardWidth - 20;
    return Math.min(preferred, preferred * available / Math.max(1, sceneTextWidth(english)));
}

export function SceneCards({ project, currentId, cover = false, frame, width = 496 }: { project: Project; currentId?: string; cover?: boolean; frame?: number; width?: number }) {
    const words = sceneWords(project.words);
    const segments = frame === undefined ? undefined : timeline(project).words;
    const gap = 6;
    const availableCardWidth = words.length ? (width - gap * (words.length - 1)) / words.length : width;
    return <div style={{ display: 'flex', flexWrap: 'nowrap', justifyContent: 'center', alignItems: 'end', gap, width }}>
        {words.map(word => {
            const highlighted = cover ? !!project.cover?.words[word.id]?.highlighted : word.id === currentId;
            const cardWidth = Math.max(1, Math.min(sceneCardWidth(word.english), availableCardWidth));
            const segment = segments?.find(item => item.word.id === word.id);
            const pulse = highlighted && frame !== undefined && segment ? sceneHighlightScale(frame, segment.from) : 1;
            return <div key={word.id} style={{ position: 'relative', zIndex: highlighted ? 2 : 1, flex: `0 1 ${cardWidth}px`, width: cardWidth, minWidth: 0, height: SCENE_CARD_HEIGHT }}>
                <div style={{ ...sceneCapsuleStyle, position: 'absolute', left: 0, bottom: 0, width: '100%', height: highlighted ? SCENE_CARD_HEIGHT + 10 : SCENE_CARD_HEIGHT, boxSizing: 'border-box', padding: '0 15px', border: highlighted ? `${annotationHighlight.border}px solid ${sceneCapsuleHighlight.ink}` : sceneCapsuleStyle.border, background: highlighted ? sceneCapsuleHighlight.fill : sceneCapsuleStyle.background, fontWeight: highlighted ? 800 : 700, overflow: 'hidden', boxShadow: highlighted ? `0 0 0 3px ${sceneCapsuleHighlight.ring}, ${sceneCapsuleHighlight.shadow}` : 'none', transform: `translateY(${highlighted ? -4 * (pulse - 1) / .08 : 0}px) scale(${pulse})`, transformOrigin: 'center bottom', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <strong style={{ fontFamily: 'inherit', fontSize: sceneCardFontSize(word.english, highlighted, cardWidth), fontWeight: 'inherit', lineHeight: 1.05, whiteSpace: 'nowrap' }}>{word.english}</strong>
                </div>
            </div>;
        })}
    </div>;
}
