import type { CoverConfig, Project, Word } from './project';
import { sceneWords } from './project';

export const defaultCover: CoverConfig = { template: 'learning-card', scale: .9, words: {} };

function coverObjectWords(words: Word[]) {
    return words.filter(word => (word.kind ?? 'object') === 'object');
}

export function coverLayout(project: Project) {
    const scale = Math.max(1080 / project.imageWidth, 1440 / project.imageHeight);
    const width = project.imageWidth * scale;
    const height = project.imageHeight * scale;
    const objects = coverObjectWords(project.words);
    const scenes = sceneWords(project.words);
    const title = project.sceneTheme?.trim() || project.title.trim() || '生活里的英语';

    return {
        photo: { x: (1080 - width) / 2, y: (1440 - height) / 2, width, height },
        objects,
        scenes,
        title,
        wordCount: objects.length + scenes.length,
        conflicts: [] as string[],
    };
}

export function coverExportReady(project: Project) {
    return !!project.image && project.words.length > 0 && project.words.every(word => word.english.trim());
}
