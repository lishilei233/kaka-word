import { sceneWords, type Project } from '../lib/project';
import { SCENE_CARD_HEIGHT } from '../lib/film-layout';
import { annotationHighlight } from './annotation-style';

function sceneTextWidth(english: string) {
    return [...english].reduce((sum, character) => sum + (/[MW@#%]/.test(character) ? 17 : /[ilI1.,' ]/.test(character) ? 7 : 12), 0);
}
export function sceneCardWidth(english: string) {
    return Math.max(64, Math.min(235, sceneTextWidth(english) + 32));
}
export function sceneCardFontSize(english: string, highlighted: boolean) {
    const preferred = highlighted ? 20 : 16;
    const available = sceneCardWidth(english) - 30;
    return Math.min(preferred, preferred * available / Math.max(1, sceneTextWidth(english)));
}

export function SceneCards({ project, currentId, cover = false }: { project: Project; currentId?: string; cover?: boolean }) {
    const words = sceneWords(project.words);
    return <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2,max-content)', justifyContent: 'center', alignItems: 'end', gap: 6 }}>
        {words.map((word, index) => {
            const highlighted = cover ? !!project.cover?.words[word.id]?.highlighted : word.id === currentId;
            const lastOdd = words.length % 2 === 1 && index === words.length - 1;
            const width = sceneCardWidth(word.english);
            return <div key={word.id} style={{ position: 'relative', zIndex: highlighted ? 2 : 1, gridColumn: lastOdd ? '1 / -1' : undefined, justifySelf: 'center', width, height: SCENE_CARD_HEIGHT }}>
                <div style={{ position: 'absolute', left: 0, bottom: 0, width: '100%', height: highlighted ? SCENE_CARD_HEIGHT + 10 : SCENE_CARD_HEIGHT, boxSizing: 'border-box', borderRadius: 9, padding: '0 15px', border: highlighted ? `${annotationHighlight.border}px solid ${annotationHighlight.ink}` : '1.5px solid #24211e30', background: highlighted ? annotationHighlight.fill : 'rgba(255,253,248,.88)', color: '#24211e', overflow: 'hidden', boxShadow: highlighted ? `0 0 0 3px rgba(255,255,255,.94), ${annotationHighlight.shadow}` : 'none', transition: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <strong style={{ fontFamily: 'Georgia, serif', fontSize: sceneCardFontSize(word.english, highlighted), lineHeight: 1.05, whiteSpace: 'nowrap' }}>{word.english}</strong>
                </div>
            </div>;
        })}
    </div>;
}
