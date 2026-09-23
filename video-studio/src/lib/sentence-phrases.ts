const wordsIn = (text: string) => [...text.matchAll(/[A-Za-z0-9]+(?:['’.-][A-Za-z0-9]+)*/g)];
const connectors = new Set('in on at by with beside near under over behind through from to into of for and but while'.split(' '));
const articles = new Set(['a', 'an', 'the']);

/** Deterministic reading groups, not linguistic or audio alignment. */
export function sentencePhrases(text: string, vocabulary: string[] = []) {
    const words = wordsIn(text);
    if (!words.length) return text ? [{ text, weight: 1 }] : [];
    const protectedCuts = new Set<number>();
    for (const term of vocabulary) {
        const tokens = wordsIn(term).map(w => w[0].toLowerCase());
        if (tokens.length < 2) continue;
        for (let i = 0; i + tokens.length <= words.length; i++) {
            if (tokens.every((token, j) => words[i + j][0].toLowerCase() === token)
                && words.slice(i, i + tokens.length - 1).every((word, j) => /^\s+$/.test(text.slice(word.index! + word[0].length, words[i + j + 1].index!)))) {
                for (let j = 1; j < tokens.length; j++) protectedCuts.add(i + j);
            }
        }
    }
    const groups: { text: string; weight: number }[] = [];
    let start = 0;
    let offset = 0;
    for (let cut = 1; cut <= words.length; cut++) {
        const previous = words[cut - 1];
        const end = cut === words.length ? text.length : words[cut].index!;
        const gap = text.slice(previous.index! + previous[0].length, end);
        const punctuation = /[,;:!?—–.] /.test(gap + ' ') || /[,;:!?—–]/.test(gap);
        const count = cut - start;
        const boundary = cut === words.length || (!protectedCuts.has(cut) && (punctuation
            || (!articles.has(previous[0].toLowerCase()) && (count >= 4
                || (count >= 2 && connectors.has(words[cut][0].toLowerCase()))))));
        if (!boundary) continue;
        const part = text.slice(offset, end);
        const weight = words.slice(start, cut).reduce((sum, w) => sum + Math.max(2, w[0].length), 0)
            + (/[.!?]/.test(gap) ? 5 : /[,;:—–]/.test(gap) ? 3 : 0);
        groups.push({ text: part, weight });
        start = cut;
        offset = end;
    }
    return groups;
}

export function activePhraseIndex(phrases: { weight: number }[], frame?: number, durationFrames?: number) {
    if (frame === undefined || durationFrames === undefined || !Number.isFinite(frame)
        || !Number.isFinite(durationFrames) || durationFrames <= 0 || frame < 0 || frame >= durationFrames) return -1;
    const total = phrases.reduce((sum, phrase) => sum + phrase.weight, 0);
    const position = frame / durationFrames * total;
    let end = 0;
    return phrases.findIndex(phrase => { end += phrase.weight; return position < end; });
}

/** Frame-driven fades keep seeking and exported frames identical to playback. */
export function phraseEmphasis(phrases: { weight: number }[], index: number, frame?: number, durationFrames?: number) {
    if (activePhraseIndex(phrases, frame, durationFrames) !== index) return 0;
    const total = phrases.reduce((sum, phrase) => sum + phrase.weight, 0);
    const start = phrases.slice(0, index).reduce((sum, phrase) => sum + phrase.weight, 0) / total * durationFrames!;
    const end = start + phrases[index].weight / total * durationFrames!;
    const fade = Math.min(5, (end - start) / 3);
    const progress = Math.max(0, Math.min(1, (frame! - start) / fade, (end - frame!) / fade));
    return progress * progress * (3 - 2 * progress);
}
