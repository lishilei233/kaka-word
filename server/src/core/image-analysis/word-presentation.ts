/** Match complete token sequences, never substrings or guessed inflections. */
export function captionPosition(caption: string, form?: string): number {
    const tokens = (value: string) => value.toLowerCase().match(/[a-z0-9]+(?:['’-][a-z0-9]+)*/g) ?? [];
    const sentence = tokens(caption), phrase = tokens(form ?? '');
    if (!phrase.length) return -1;
    return sentence.findIndex((_, index) => phrase.every((token, offset) => sentence[index + offset] === token));
}

type WordEvidence = { english: string; kind?: string; captionForm?: string; captionEvidence?: string };
const nonLexical = new Set(['be', 'am', 'is', 'are', 'was', 'were', 'been', 'being', 'can', 'could', 'may', 'might', 'must', 'shall', 'should', 'will', 'would']);
export function captionVerbs<T extends WordEvidence>(words: T[], caption: string): T[] {
    const seen = new Set<string>();
    return words.filter(word => word.kind === 'verb' && word.captionEvidence === caption
        && !nonLexical.has(word.english.trim().toLowerCase()) && captionPosition(caption, word.captionForm) >= 0)
        .sort((a, b) => captionPosition(caption, a.captionForm) - captionPosition(caption, b.captionForm))
        .filter(word => { const key = word.english.trim().toLowerCase(); if (seen.has(key)) return false; seen.add(key); return true; })
        .slice(0, 3);
}

export function applyVerbEvidence<T extends WordEvidence>(words: T[], caption: string, matches: { english: string; captionForm: string }[] = []): T[] {
    return words.map(word => {
        if (word.kind !== 'verb') return word;
        const match = matches.find(match => match.english.trim().toLowerCase() === word.english.trim().toLowerCase());
        return { ...word, captionForm: match?.captionForm, captionEvidence: match ? caption : undefined };
    });
}

type PositionedObject = { id: string; box: { x: number; y: number; width: number; height: number }; anchor?: { x: number; y: number } };
export function finalizeSceneWords<T extends WordEvidence & { relatedObjectID?: string }>(words: T[], objects: PositionedObject[], caption: string, matches: { english: string; captionForm: string }[] | undefined, limit: number): (T & Partial<Pick<PositionedObject, 'box' | 'anchor'>>)[] {
    const valid = applyVerbEvidence(words, caption, matches);
    const states = valid.filter(word => word.kind === 'adjective').flatMap(word => {
        const object = objects.find(object => object.id === word.relatedObjectID);
        if (!object || object.box.width <= 0 || object.box.height <= 0) return [];
        return [{ ...word, box: object.box, anchor: object.anchor }];
    });
    return [...captionVerbs(valid, caption), ...states].slice(0, limit);
}
