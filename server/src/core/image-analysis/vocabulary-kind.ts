import { z } from 'zod';

export const vocabularyKinds = ['noun', 'adjective', 'verb'] as const;
export type VocabularyKind = typeof vocabularyKinds[number];
export const vocabularyKindTitles: Record<VocabularyKind, string> = { noun: '名词', adjective: '形容词', verb: '动词' };
const legacyKinds = { object: 'noun', state: 'adjective', action: 'verb' } as const;
const legacyValues = { noun: 'object', adjective: 'state', verb: 'action' } as const;
export const vocabularyFormatHeader = 'X-Vocabulary-Format';
export const vocabularyFormat = 'pos-v1';

export function normalizeVocabularyKind(value: unknown): unknown {
    return typeof value === 'string' && Object.hasOwn(legacyKinds, value) ? legacyKinds[value as keyof typeof legacyKinds] : value;
}
export const vocabularyKindSchema = z.preprocess(normalizeVocabularyKind, z.enum(vocabularyKinds));
export const nonNounKindSchema = z.preprocess(normalizeVocabularyKind, z.enum(['adjective', 'verb']));

/** Normalize a word before discriminated-union validation, without changing its ID. */
export function normalizeWordKind(value: unknown): unknown {
    if (!value || typeof value !== 'object' || !('kind' in value)) return value;
    return { ...value, kind: normalizeVocabularyKind(value.kind) };
}

/** Only transform vocabulary fields, never SSE names or arbitrary user text. */
export function vocabularyResponse<T>(value: T, requestedFormat?: string): unknown {
    if (Array.isArray(value)) return value.map(item => vocabularyResponse(item, requestedFormat));
    if (!value || typeof value !== 'object') return value;
    return Object.fromEntries(Object.entries(value).map(([key, item]) => {
        if (key === 'kind') {
            const canonical = normalizeVocabularyKind(item);
            return [key, requestedFormat === vocabularyFormat ? canonical
                : typeof canonical === 'string' && Object.hasOwn(legacyValues, canonical) ? legacyValues[canonical as VocabularyKind] : item];
        }
        return [key, vocabularyResponse(item, requestedFormat)];
    }));
}
