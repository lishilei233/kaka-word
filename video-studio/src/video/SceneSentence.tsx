import React from 'react';

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
    const parts: { text: string; highlighted: boolean }[] = [];
    let last = 0;
    for (const match of text.matchAll(matcher)) {
        const index = match.index ?? 0;
        if (index > last) parts.push({ text: text.slice(last, index), highlighted: false });
        const token = match[0].toLowerCase().replace(/[^a-z]/g, '');
        const highlighted = terms.some(term => token === term) || termStems.some(value => stem(token) === value);
        parts.push({ text: match[0], highlighted });
        last = index + match[0].length;
    }
    if (last < text.length) parts.push({ text: text.slice(last), highlighted: false });
    return parts;
}

// Use the same conservative sizing in Player and Remotion, including long edited sentences.
export function SceneSentence({ english, chinese, width, vocabulary = [] }: { english: string; chinese: string; width: number; vocabulary?: string[] }) {
    let size = 22;
    const lines = (text: string, font: number) => Math.max(1, Math.ceil([...text].reduce((sum, c) => sum + (/[^\x00-\xff]/.test(c) ? font : font * .65), 0) / Math.max(40, width - 34)));
    while (size > 7 && lines(english, size) * size * 1.3 + lines(chinese, size * .78) * size * .78 * 1.4 + 8 > 116) size -= .5;
    return <>
        <div style={{ fontFamily: 'Georgia, "Times New Roman", serif', fontSize: size, lineHeight: 1.3, fontWeight: 700, overflowWrap: 'anywhere', color: 'rgba(36,33,30,.86)' }}>{captionParts(english, vocabulary).map((part, index) => <span key={`${part.text}-${index}`} style={part.highlighted ? { background: '#ffd84d', borderRadius: 5, padding: '0 4px', boxShadow: '0 0 0 2px rgba(255,255,255,.9)', fontWeight: 900 } : undefined}>{part.text}</span>)}</div>
        <div style={{ marginTop: 6, fontSize: size * .78, lineHeight: 1.35, overflowWrap: 'anywhere', fontWeight: 600, color: 'rgba(36,33,30,.56)' }}>{chinese}</div>
    </>;
}
