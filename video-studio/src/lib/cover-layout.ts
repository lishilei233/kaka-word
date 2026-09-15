import { annotationHighlight } from '../video/annotation-style';
import { filmLayout } from './film-layout';
import { annotationLayout, completeAnnotationLayout } from './annotation-layout';
import type { Project, CoverConfig } from './project';

export const defaultCover: CoverConfig = { template: 'learning-card', scale: 1, words: {} };
export function coverLayout(project: Project) {
    const scale = Math.max(1080 / project.imageWidth, 1440 / project.imageHeight);
    const width = project.imageWidth * scale, height = project.imageHeight * scale;
    const photo = { x: (1080-width)/2, y: (1440-height)/2, width, height };
    const viewport = { x: 0, y: 0, width: 1080, height: 1440 };
    const toViewport = (point: { x: number; y: number }) => ({
        x: (photo.x + point.x * width) / 1080,
        y: (photo.y + point.y * height) / 1440,
    });
    const config = project.cover ?? defaultCover;
    const videoFrame = filmLayout(project).photoImage;
    const videoLayout = annotationLayout(project.words, videoFrame);
    const objects = project.words.map(word => {
        const placement = videoLayout.placements.find(p => p.id === word.id);
        const inherited = placement ? { x: (placement.labelCenter.x-videoFrame.x)/videoFrame.width, y: (placement.labelCenter.y-videoFrame.y)/videoFrame.height } : word.labelCenterOverride;
        const labelScale = 2 * config.scale * (config.words[word.id]?.scale ?? 1) * (config.words[word.id]?.highlighted ? annotationHighlight.scale : 1);
        return ({
        id: word.id, english: word.english, box: word.box,
        labelScale,
        labelWidthOverride: Math.max(72, [...word.english].reduce((sum, c) => sum + (/[MW@#%]/.test(c) ? 16 : /[ilI1.,' ]/.test(c) ? 6 : 11), 0) + 32) * labelScale,
        labelCenterOverride: toViewport(config.words[word.id]?.labelCenterOverride ?? inherited ?? { x: word.box.x + word.box.width/2, y: word.box.y + word.box.height/2 }),
        targetCenterOverride: toViewport(config.words[word.id]?.targetCenterOverride ?? word.targetCenterOverride ?? { x: word.box.x + word.box.width/2, y: word.box.y + word.box.height/2 }),
    }); });
    const layout = completeAnnotationLayout(objects, viewport);
    const conflicts = new Set<string>();
    for (const p of layout.placements) {
        const a = p.labelFrame;
        if (a.x < 10-.001 || a.y < 10-.001 || a.x+a.width > 1070+.001 || a.y+a.height > 1430+.001) conflicts.add(p.id);
        for (const q of layout.placements) {
            const b = q.labelFrame;
            if (p.id !== q.id && a.x < b.x+b.width && a.x+a.width > b.x && a.y < b.y+b.height && a.y+a.height > b.y) { conflicts.add(p.id); conflicts.add(q.id); }
        }
    }
    return { ...layout, photo, conflicts: [...conflicts] };
}
export function coverExportReady(project: Project) {
    return !!project.image && project.words.length > 0 && project.words.every(w => w.english.trim()) && coverLayout(project).conflicts.length === 0;
}
