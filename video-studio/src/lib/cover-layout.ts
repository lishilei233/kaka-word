import type { CoverConfig, Project, Word } from './project';
import { sceneWords } from './project';

export const defaultCover: CoverConfig = { template: 'learning-card', scale: .9, words: {} };

export type BalancedCoverItem<T> = { value: T; width: number; order: number };

function coverRowWidth<T>(row: BalancedCoverItem<T>[], gap: number) {
    return row.reduce((sum, item) => sum + item.width, 0) + Math.max(0, row.length - 1) * gap;
}

export function balancedCoverRows<T>(items: BalancedCoverItem<T>[], availableWidth: number, gap: number, maxPerRow = 5) {
    if (!items.length) return [];
    const minimumRows = Math.max(1, Math.ceil(items.length / maxPerRow));
    const maximumRows = Math.max(minimumRows, Math.min(3, items.length));
    const sorted = [...items].sort((a, b) => b.width - a.width || a.order - b.order);

    const distribute = (rowCount: number) => {
        const smallRowSize = Math.floor(items.length / rowCount);
        const largerRows = items.length % rowCount;
        const capacities = Array.from({ length: rowCount }, (_, index) => smallRowSize + (index < largerRows ? 1 : 0));
        const rows = capacities.map(() => [] as BalancedCoverItem<T>[]);

        for (const item of sorted) {
            const candidates = rows
                .map((row, index) => ({ index, width: coverRowWidth(row, gap), remaining: capacities[index] - row.length }))
                .filter(candidate => candidate.remaining > 0)
                .sort((a, b) => a.width - b.width || b.remaining - a.remaining || a.index - b.index);
            rows[candidates[0].index].push(item);
        }

        return rows
            .map(row => ({ items: row.sort((a, b) => a.order - b.order), width: coverRowWidth(row, gap) }))
            .sort((a, b) => b.width - a.width || (a.items[0]?.order ?? 0) - (b.items[0]?.order ?? 0));
    };

    let rows = distribute(minimumRows);
    for (let rowCount = minimumRows + 1; rows.some(row => row.width > availableWidth) && rowCount <= maximumRows; rowCount += 1) {
        rows = distribute(rowCount);
    }
    return rows;
}

function coverObjectWords(words: Word[]) {
    return words.filter(word => (word.kind ?? 'object') === 'object');
}

export function coverLayout(project: Project) {
    const scale = Math.max(1080 / project.imageWidth, 1440 / project.imageHeight);
    const width = project.imageWidth * scale;
    const height = project.imageHeight * scale;
    const objects = coverObjectWords(project.words);
    const scenes = sceneWords(project.words);
    const title = project.cover?.title?.trim() || project.sceneTheme?.trim() || project.title.trim() || '生活里的英语';

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
