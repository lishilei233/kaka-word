import React from 'react';
import { activePhraseIndex, phraseEmphasis, sentencePhrases } from '../lib/sentence-phrases';

export function captionParts(text: string, vocabulary: string[] = []) {
    const terms = vocabulary.filter(Boolean).map(term => term.toLowerCase().replace(/[^a-z]+/g, '')).filter(Boolean);
    if (!terms.length) return [{ text, highlighted: false }];
    const stem = (word: string) => {
        let value = word.toLowerCase().replace(/[^a-z]/g, '');
        if (value.length > 5 && value.endsWith('ies')) value = `${value.slice(0, -3)}y`;
        else if (value.length > 4 && value.endsWith('ing')) value = value.slice(0, -3);
        else if (value.length > 4 && value.endsWith('ed')) value = value.slice(0, -2);
        else if (value.length > 3 && value.endsWith('es')) value = value.slice(0, -2);
        // Include short verbs such as run/runs; the previous length guard
        // accidentally excluded this very common three-letter base form.
        else if (value.length > 2 && value.endsWith('s')) value = value.slice(0, -1);
        return value;
    };
    const termStems = terms.map(stem);
    const matcher = /[A-Za-z]+(?:'[A-Za-z]+)?/g;
    const matches = [...text.matchAll(matcher)];
    const phraseWordIndices = new Set<number>();
    for (const term of vocabulary) {
        const tokens = [...term.matchAll(matcher)].map(match => match[0].toLowerCase());
        if (tokens.length < 2) continue;
        for (let i = 0; i + tokens.length <= matches.length; i++) {
            if (tokens.every((token, j) => matches[i + j][0].toLowerCase() === token)) {
                for (let j = 0; j < tokens.length; j++) phraseWordIndices.add(matches[i + j].index!);
            }
        }
    }
    const parts: { text: string; highlighted: boolean }[] = [];
    let last = 0;
    for (const match of text.matchAll(matcher)) {
        const index = match.index ?? 0;
        if (index > last) parts.push({ text: text.slice(last, index), highlighted: false });
        const token = match[0].toLowerCase().replace(/[^a-z]/g, '');
        const highlighted = phraseWordIndices.has(index) || terms.some(term => token === term) || termStems.some(value => stem(token) === value);
        parts.push({ text: match[0], highlighted });
        last = index + match[0].length;
    }
    if (last < text.length) parts.push({ text: text.slice(last), highlighted: false });
    return parts;
}

// Use the same conservative sizing in Player and Remotion, including long edited sentences.
export function SceneSentence({ english, chinese, width, vocabulary = [], chineseOpacity = 1, audioFrame, audioDurationFrames }: { english: string; chinese: string; width: number; vocabulary?: string[]; chineseOpacity?: number; audioFrame?: number; audioDurationFrames?: number }) {
    const phrases = sentencePhrases(english, vocabulary);
    const active = activePhraseIndex(phrases, audioFrame, audioDurationFrames);
    let size = 22;
    const lines = (text: string, font: number) => Math.max(1, Math.ceil([...text].reduce((sum, c) => sum + (/[^\x00-\xff]/.test(c) ? font : font * .65), 0) / Math.max(40, width - 34)));
    const animated = Number.isFinite(audioDurationFrames) && audioDurationFrames! > 0;
    while (size > 7 && lines(english, size * (animated ? 1.1 : 1)) * size * 1.3 + lines(chinese, size * .78) * size * .78 * 1.4 + 8 > 116) size -= .5;
    return <>
        <div style={{ fontFamily: 'Georgia, "Times New Roman", serif', fontSize: size, lineHeight: 1.3, fontWeight: 700, overflowWrap: 'anywhere', color: 'rgba(36,33,30,.86)' }}>{phrases.map((phrase, index) => {
            const emphasis = phraseEmphasis(phrases, index, audioFrame, audioDurationFrames);
            let offset = 0;
            const parts = captionParts(phrase.text, vocabulary).map(part => {
                const start = offset; offset += part.text.length;
                return { ...part, start, end: offset };
            });
            return <span key={index} data-phrase-active={index === active ? 'true' : undefined}>{[...phrase.text.matchAll(/\s+|\S+/g)].map((match, wordIndex) => {
                if (/^\s+$/.test(match[0])) return match[0];
                const start = match.index!, end = start + match[0].length;
                return <span key={wordIndex} style={{ display: 'inline-block', maxWidth: '100%', verticalAlign: 'baseline', paddingInline: animated ? '.05em' : 0 }}><span style={{ display: 'inline-block', maxWidth: '100%', transform: `scale(${1 + .08 * emphasis})`, transformOrigin: 'center center', backgroundColor: `rgba(255,216,77,${emphasis})`, borderRadius: 4 }}>{parts.filter(part => part.end > start && part.start < end).map((part, partIndex) => <span key={partIndex} style={part.highlighted ? { textDecorationLine: 'underline', textDecorationColor: 'rgba(156,119,40,.45)', textDecorationThickness: '1px', textUnderlineOffset: '3px' } : undefined}>{phrase.text.slice(Math.max(start, part.start), Math.min(end, part.end))}</span>)}</span></span>;
            })}</span>;
        })}</div>
        <div style={{ marginTop: 6, fontSize: size * .78, lineHeight: 1.35, overflowWrap: 'anywhere', fontWeight: 600, color: 'rgba(36,33,30,.56)', opacity: chineseOpacity }}>{chinese}</div>
    </>;
}
