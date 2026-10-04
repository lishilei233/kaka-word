import { normalizeWordKind } from './vocabulary-kind.js';
import { z } from 'zod';
import { captionSentenceInstruction } from './prompts.js';
import { photoCaptionSchema, normalizeCaption } from './types.js';

const coordinate = z.number().min(0).max(1);
const box = z.object({ x: coordinate, y: coordinate, width: coordinate, height: coordinate })
    .refine(b => b.width > 0 && b.height > 0 && b.x + b.width <= 1.000001 && b.y + b.height <= 1.000001);
const vocabulary = {
    id: z.string().min(1).max(40), english: z.string().trim().min(1).max(60),
    chinese: z.string().min(1).max(60), ipa: z.string().max(80),
    example: z.string().min(1).max(180).optional(),
    exampleChinese: z.string().min(1).max(180).optional(),
};
export const studioSceneSchema = z.object({
    theme: z.string().min(1).max(100),
    words: z.array(z.preprocess(normalizeWordKind, z.discriminatedUnion('kind', [
        z.object({ ...vocabulary, kind: z.literal('noun'), box, anchor: z.object({ x: coordinate, y: coordinate }).optional() }),
        z.object({ ...vocabulary, kind: z.literal('verb'), captionForm: z.string().max(120).optional(), captionEvidence: z.string().max(441).optional() }),
        z.object({ ...vocabulary, kind: z.literal('adjective'), relatedObjectID: z.string().max(40).optional(), box: box.optional(), anchor: z.object({ x: coordinate, y: coordinate }).optional() }),
    ]))).max(20).refine(words => new Set(words.map(w => w.id)).size === words.length),
    ...photoCaptionSchema.shape,
    interaction: z.object({ english: z.string().min(1).max(220), chinese: z.string().min(1).max(220) }),
}).transform(normalizeCaption);
export type StudioScene = z.infer<typeof studioSceneSchema>;
export type StudioSceneInput = {
    image: Uint8Array;
    mimeType: string;
    context: string;
    objects: { id?: string; english: string; chinese: string; box?: { x: number; y: number; width: number; height: number } }[];
    masteredWords?: string[];
    maxSceneWords?: number;
    signal?: AbortSignal;
};

/**
 * 识别场景主题，以及由场景证据支持的动词和形容词。
 * 名词已经由第一次识别完成，这里只补充 verb/adjective，避免重复返回物体。
 *
 * App 与 video-studio 共用场景分析；形容词通过物体 ID 关联定位。
 */
export function studioScenePrompt(input: Pick<StudioSceneInput, 'context' | 'objects' | 'masteredWords' | 'maxSceneWords'>) {
    const maxSceneWords = Math.min(Math.max(input.maxSceneWords ?? 10, 0), 10);
    return `Create a beginner English lesson around ONE coherent everyday scene in this photo.
User background (terminology context only, not visual evidence): ${JSON.stringify(input.context)}. It may disambiguate a visible item, but MUST NOT add any fact that is not directly visible in the photo.
The noun vocabulary has already been recognized by the app's authoritative object-recognition pipeline: ${JSON.stringify(input.objects)}. Use as many supplied nouns as fit naturally in the description, prioritizing visually central and distinctive objects. Nouns are optional: never force a word if it makes the sentence awkward, repetitive, or less accurate. Do not return nouns again in the words array. Supplied boxes use normalized image coordinates (x, y, width, height) with a top-left origin; use them to identify the correct instance when several objects share the same name.
The learner already knows these English terms: ${JSON.stringify(input.masteredWords ?? [])}. When equally reliable verbs or adjectives are available, prefer useful terms outside this list. This is only a preference: never invent or weaken visual evidence to avoid a known term.
Return only useful verbs and adjectives in words. Their count is determined by the scene; do not fill a quota. Include a verb or adjective ONLY when directly supported by visible evidence in the photo; user background is never sufficient evidence. A still image of damage does not prove a past fall. Texture, temperature, taste, feelings, intention, purpose, ownership, relationships and off-camera events must not be invented. Static scenes are valid and may return an empty words array; do not force verbs or adjectives. Return at most ${maxSceneWords} verbs and adjectives.
Inspect the visible condition of each supplied object separately from choosing actions and writing the caption. Static does NOT mean stateless. Include a useful, clearly evidenced object state even when there is no action and even when that adjective is absent from the caption. Not every object needs a state: return no state for ordinary, ambiguous, hidden, or unsupported conditions, and never fill a per-object quota.
For containers such as cups, glasses, bowls and bottles, check the visible interior or liquid level: use full (满的) when contents visibly fill the container to or near the rim; use empty (空的) when the clearly visible interior contains nothing. Merely seeing some water does not mean full. A hidden interior, opaque wall, obscured rim or uncertain contents cannot prove empty or full. For example, two cups can yield full linked to the filled cup's ID and empty linked to the empty cup's ID. Link these states to the container, not to the water. Other useful directly visible contrasts include open/closed and broken/intact. Do not return opposing states for the same object.
Copy relatedObjectID exactly from the supplied object list; never use the adjective ID, an object name, or a literal placeholder. Return at most three useful verb candidates so obvious object states are not crowded out by actions, while respecting the total word limit above. No verb or adjective is mandatory.
For a static arrangement of inanimate objects, do not return agentive or inferred terms such as wait, waiting, ready, prepared, expect, watch, welcome, enjoy, want, need, or belong. Use neutral visible placement language in captions: “is on,” “sits on,” “stands beside,” “lies near,” “hangs above,” or “is placed next to.” Never say an inanimate object “waits” or is “ready” merely because it is arranged for possible use.
Use natural terms (egg white, not ambiguous white), base-form verbs and accurate adjectives (break vs broken). Avoid redundant terms. Supply accurate American IPA and the most common, context-appropriate simplified Chinese meaning for what is visibly shown; avoid literal calques, unnecessary “的”, obscure dictionary senses, and stiff textbook wording. After selecting the supported verbs and adjectives, use them only when they fit the description naturally; never distort the sentence to force vocabulary coverage.
Return JSON only: {"theme":"简短中文主题", "words":[{"id":"w1","kind":"verb","english":"practice","chinese":"练习","ipa":"/ˈpræktɪs/","example":"The child practices writing.","exampleChinese":"孩子在练习写字。"},{"id":"w2","kind":"adjective","relatedObjectID":"<supplied object id>","english":"empty","chinese":"空的","ipa":"/ˈempti/","example":"The cup is empty.","exampleChinese":"杯子是空的。"}], "caption":"One accurate natural sentence.","captionChinese":"自然中文", "captionSentences":[{"english":"One accurate natural sentence.","chinese":"自然中文"}], "interaction":{"english":"One short engaging question?","chinese":"中文问题？"}}
Return one factual English description and one natural Chinese description; do not return style variants.
Every returned word kind must be verb or adjective and MUST NOT have coordinates. For every adjective, include relatedObjectID identifying the ONE supplied object it visibly describes. Omit adjectives without a clear visible object association. For every verb, include captionForm with its exact inflected verb or verb phrase in your caption; english must be its base form. Return no auxiliary or copular verbs as verb vocabulary. ${captionSentenceInstruction} Every detail must be supported by the photo. Strongly evidenced everyday inference is allowed: a person may be called a customer or employee only when clothing, signage, position, and visible activity support that identity; waiting requires visible queueing, attentive posture, or a clear target; ownership requires direct holding or use; cause-and-effect language requires a visible relationship. Otherwise use neutral terms such as person, people, near, or beside. The Chinese caption must independently express the same supported meaning in fluent, conversational simplified Chinese rather than mirror English word order. Do not anthropomorphize objects or infer sensitive attributes. The interaction question must be answerable from visible photo content and must not presume an unobserved event.
BAD: “The ready drinks wait on the counter next to the paper bags.” / “准备好的饮料在柜台上等待，旁边是纸袋。” This invents readiness, personifies drinks, and translates the error literally.
GOOD: “Drinks and paper bags sit on the counter.” / “柜台上放着饮料和纸袋。” This states only the visible arrangement in natural English and Chinese.`;
}
