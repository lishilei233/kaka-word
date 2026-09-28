import type { CoverConfig, Project, Word } from './project';
import { sceneWords } from './project';

export const legacyDefaultCover: CoverConfig = { template: 'learning-card', scale: .9, words: {} };
export const defaultCover: CoverConfig = { template: 'scene-question', scale: .9, words: {} };

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
    return !!project.image && project.words.length > 0 && project.words.every(word => word.english.trim()) && coverConflicts(project).length === 0;
}

export const coverAudiences = [
    { id: 'adult', label: '成人日常' },
    { id: 'family', label: '亲子启蒙' },
    { id: 'student', label: '学生积累' },
] as const;
export const defaultCoverPhoto = { zoom: 1, x: .5, y: .5 };
export const isQuestionCover = (project: Project) => (project.cover?.template ?? defaultCover.template) === 'scene-question';

export function selectedCoverWords(project: Project) {
    const ids = project.cover?.selectedWordIds;
    if (ids) return ids.flatMap(id => project.words.find(word => word.id === id) ?? []).slice(0, 3);
    const prioritized = [...project.words.filter(word => project.cover?.words[word.id]?.highlighted), ...project.words];
    return prioritized.filter((word, index) => prioritized.findIndex(other => other.id === word.id) === index).slice(0, 3);
}

export function coverQuestionTitle(project: Project) {
    const audience = project.cover?.audience ?? 'adult';
    const edited = project.cover?.audienceTitles?.[audience];
    if (edited !== undefined) return edited.trim();
    const scene = project.sceneTheme?.trim() || (project.title.trim() !== '生活里的英语' ? project.title.trim() : '') || '这些东西';
    if (audience === 'family') return `和孩子认一认，${scene}英语怎么说？`;
    if (audience === 'student') return `${scene}，这些词你会吗？`;
    return `${scene}，英语怎么说？`;
}

// Conservative glyph advances for the pinned heavy PingFang/Arial cover fonts.
// Explicit line breaks make browser preview and Remotion export deterministic.
export function coverTextWidth(text: string, fontSize: number) {
    return Array.from(text).reduce((sum, char) => sum + (/\s/.test(char) ? .35 : /[ilI.,!':;|]/.test(char) ? .38 : /[mwMW@%]/.test(char) ? 1.05 : /[A-Z0-9]/.test(char) ? .8 : /[a-z]/.test(char) ? .68 : 1.04), 0) * fontSize;
}

export function fitCoverTitle(title: string) {
    const text = title.trim();
    const fits = (lines: string[], fontSize: number) => lines.length > 0 && lines.length <= 2 && lines.every(line => line.trim() && coverTextWidth(line, fontSize) <= 936);
    const explicit = text.includes('\n') ? text.split('\n').map(line => line.trim()) : undefined;
    // Prefer a complete scene phrase followed by a complete question.
    const semantic = Array.from(text.matchAll(/[，,：:；;]/g)).map(match => [text.slice(0, match.index! + 1), text.slice(match.index! + 1).trim()]);
    for (const groups of [explicit ? [explicit] : semantic, explicit ? [] : undefined]) {
        if (groups) {
            for (let fontSize = 116; fontSize >= 72; fontSize -= 2) {
                const lines = groups.find(lines => fits(lines, fontSize));
                if (lines) return { lines, fontSize, fits: true };
            }
        } else {
            const tokens = text.match(/[a-zA-Z0-9]+(?:['’-][a-zA-Z0-9]+)*|[^a-zA-Z0-9]/gu) ?? [];
            for (let fontSize = 116; fontSize >= 72; fontSize -= 2) {
                if (fits([text], fontSize)) return { lines: [text], fontSize, fits: true };
                const pairs = tokens.slice(1).map((_, index) => [tokens.slice(0, index + 1).join('').trim(), tokens.slice(index + 1).join('').trim()])
                    .filter(lines => fits(lines, fontSize) && !/^[，。！？、：；,.!?;:）】]/.test(lines[1]))
                    .sort((a, b) => Math.abs(coverTextWidth(a[0], 1) - coverTextWidth(a[1], 1)) - Math.abs(coverTextWidth(b[0], 1) - coverTextWidth(b[1], 1)));
                if (pairs.length) return { lines: pairs[0], fontSize, fits: true };
            }
        }
    }
    return { lines: [title], fontSize: 72, fits: false };
}

export function questionCoverLayout(project: Project) {
    const crop = project.cover?.photo ?? defaultCoverPhoto;
    const scale = Math.max(1080 / project.imageWidth, 1440 / project.imageHeight) * crop.zoom;
    const width = project.imageWidth * scale, height = project.imageHeight * scale;
    const title = coverQuestionTitle(project);
    const heading = fitCoverTitle(title);
    const words = selectedCoverWords(project);
    const wordRows: { words: Word[]; width: number }[] = [];
    let wordFontSize = 36;
    while (wordFontSize > 28 && words.some(word => coverTextWidth(word.english, wordFontSize) + 48 > 936)) wordFontSize -= 2;
    for (const word of words) {
        const width = coverTextWidth(word.english, wordFontSize) + 48;
        const last = wordRows.at(-1);
        if (last && last.width + 16 + width <= 936) { last.words.push(word); last.width += 16 + width; }
        else wordRows.push({ words: [word], width });
    }
    const conflicts = [] as string[];
    if (!heading.fits) conflicts.push(title ? '标题超过两行，请缩短标题或调整换行。' : '请填写封面标题。');
    if (wordRows.some(row => row.width > 936)) conflicts.push('精选英文词过长，请改选较短的词或隐藏该词。');
    return {
        title, heading, words, wordRows, wordFontSize, conflicts,
        position: project.cover?.titlePosition ?? 'top',
        photo: { x: (1080 - width) * crop.x, y: (1440 - height) * crop.y, width, height },
    };
}

export function coverConflicts(project: Project) {
    return isQuestionCover(project) ? questionCoverLayout(project).conflicts : coverLayout(project).conflicts;
}

export function moveCoverPhoto(project: Project, deltaX: number, deltaY: number) {
    const photo = project.cover?.photo ?? defaultCoverPhoto;
    const frame = questionCoverLayout(project).photo;
    const clamp = (value: number) => Math.max(0, Math.min(1, value));
    return {
        ...photo,
        x: frame.width > 1080 ? clamp(photo.x - deltaX / (frame.width - 1080)) : .5,
        y: frame.height > 1440 ? clamp(photo.y - deltaY / (frame.height - 1440)) : .5,
    };
}

export function coverCopySource(project: Project) {
    return JSON.stringify([project.image, project.sceneTheme, project.caption, project.captionChinese,
        project.words.map(({ id, english, chinese, kind }) => [id, english, chinese, kind])]);
}

export function applyCoverCandidates(project: Project, source: string, candidates: NonNullable<CoverConfig['candidates']>) {
    if (source !== coverCopySource(project)) return project;
    return { ...project, cover: { ...(project.cover ?? defaultCover), candidates, candidateSource: source } };
}

export function cleanCoverSelection(project: Project): Project {
    if (!project.cover) return project;
    return { ...project, cover: { ...project.cover,
        words: Object.fromEntries(Object.entries(project.cover.words).filter(([id]) => project.words.some(word => word.id === id))),
        ...(project.cover.selectedWordIds ? { selectedWordIds: project.cover.selectedWordIds.filter(id => project.words.some(word => word.id === id)) } : {}),
    } };
}
