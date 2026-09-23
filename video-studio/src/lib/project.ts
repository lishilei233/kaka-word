import { z } from 'zod';

const position = z.number().min(0).max(1);
const boxSchema = z.object({ x: position, y: position, width: position, height: position }).refine(
    box => box.x + box.width <= 1 && box.y + box.height <= 1,
    '物体范围不能超出照片',
);
const pointSchema = z.object({ x: position, y: position });
export const voiceIdSchema = z.enum([
    'English_LovelyGirl', 'English_PlayfulGirl', 'English_AttractiveGirl', 'conversational_female_2_v1',
    'English_Kind-heartedGirl', 'English_Graceful_Lady', 'English_Insightful_Speaker',
    'English_radiant_girl', 'English_magnetic_voiced_man',
]);
export const voiceOptions = [
    { id: 'English_LovelyGirl', label: '可爱女声' },
    { id: 'English_PlayfulGirl', label: '俏皮女声' },
    { id: 'English_AttractiveGirl', label: '魅力女声' },
    { id: 'conversational_female_2_v1', label: '自然对话女声' },
    { id: 'English_Kind-heartedGirl', label: '亲切女声' },
    { id: 'English_Graceful_Lady', label: '温柔女声' },
    { id: 'English_Insightful_Speaker', label: '知性女声' },
    { id: 'English_radiant_girl', label: '明亮女声' },
    { id: 'English_magnetic_voiced_man', label: '磁性男声' },
] as const;
const currentWordSchema = z.object({
    id: z.string().min(1).max(80), english: z.string().trim().min(1).max(60),
    chinese: z.string().max(60), ipa: z.string().max(80),
    kind: z.enum(['object', 'action', 'state']).optional(),
    needsLocation: z.boolean().optional(),
    box: boxSchema.optional(), labelCenterOverride: pointSchema.optional(), targetCenterOverride: pointSchema.optional(),
    audio: z.string().regex(/^\/studio-api\/assets\/[a-f0-9-]+\.wav$/).optional(),
    audioSeconds: z.number().positive().max(30).optional(),
});
const legacyWordSchema = currentWordSchema.omit({ box: true, labelCenterOverride: true, targetCenterOverride: true }).extend({ x: position, y: position, targetX: position, targetY: position });
const imageAsset = z.string().regex(/^\/studio-api\/assets\/[a-f0-9-]+\.jpg$/);
const legacyCaptionVariantSchema = z.object({ caption: z.string().max(220), captionChinese: z.string().max(220) });
const legacyCaptionVariantsSchema = z.object({ serious: legacyCaptionVariantSchema, funny: legacyCaptionVariantSchema, literary: legacyCaptionVariantSchema });
export const socialPostSchema = z.object({ title: z.string().max(80), body: z.string().max(4000), hashtags: z.array(z.string().max(40)).max(12) });
export const socialCopySchema = z.object({ xiaohongshu: socialPostSchema, douyin: socialPostSchema, channels: socialPostSchema });
export type SocialCopy = z.infer<typeof socialCopySchema>;
export const coverSchema = z.object({
    template: z.literal('learning-card').default('learning-card'),
    title: z.string().max(40).optional(),
    scale: z.number().min(.6).max(1.6).default(.9),
    words: z.record(z.object({
        scale: z.number().min(.75).max(1.5).default(1),
        highlighted: z.boolean().optional(),
        labelCenterOverride: pointSchema.optional(),
        targetCenterOverride: pointSchema.optional(),
    })).default({}),
});
export type CoverConfig = z.infer<typeof coverSchema>;
const legacyProjectFields = {
    analysisMode: z.enum(['objects', 'scene']).optional(),
    sceneContext: z.string().max(500).optional(),
    sceneTheme: z.string().max(100).optional(),
    interaction: z.object({ enabled: z.boolean(), english: z.string().max(220), chinese: z.string().max(220),
        arrowEnabled: z.boolean().optional(), arrowTarget: pointSchema.optional(),
        audio: z.string().regex(/^\/studio-api\/assets\/[a-f0-9-]+\.wav$/).optional(), audioSeconds: z.number().positive().max(60).optional() }).optional(),
    socialCopyStale: z.boolean().optional(),
    cover: coverSchema.optional(),
    title: z.string().max(80),
    caption: z.string().max(441).default(''), captionChinese: z.string().max(440).default(''),
    captionVariants: legacyCaptionVariantsSchema.optional(),
    selectedCaptionStyle: z.enum(['serious', 'funny', 'literary']).default('serious'),
    socialCopy: socialCopySchema.optional(),
    videoTemplate: z.enum(['direct', 'camera']).default('direct'),
    directIntroSeconds: z.number().min(0).max(5).default(.5),
    captionAudio: z.string().regex(/^\/studio-api\/assets\/[a-f0-9-]+\.wav$/).optional(),
    captionAudioSeconds: z.number().positive().max(60).optional(),
    voiceId: voiceIdSchema.default('English_Graceful_Lady'),
    speechSpeed: z.number().min(0.5).max(2).default(0.92),
    safeTop: z.number().min(120).max(280).default(120),
    safeBottom: z.number().min(240).max(480).default(240),
    safeRight: z.number().min(0).max(160).default(0),
    image: imageAsset.optional(), video: z.string().regex(/^\/studio-api\/assets\/[a-f0-9-]+\.(mp4|mov|webm)$/).optional(),
    imageWidth: z.number().positive().max(12000), imageHeight: z.number().positive().max(12000),
    captureSeconds: z.number().min(0).max(3600), introSeconds: z.number().min(0.5).max(10),
    pauseSeconds: z.number().min(0).max(5),
};
const { captionVariants: _legacyVariants, selectedCaptionStyle: _legacyStyle, ...sharedProjectFields } = legacyProjectFields;
export const captionSentenceSchema = z.object({
    english: z.string().max(220), chinese: z.string().max(220),
    audio: z.string().regex(/^\/studio-api\/assets\/[a-f0-9-]+\.wav$/).optional(),
    audioSeconds: z.number().positive().max(60).optional(),
});
export type CaptionSentence = z.infer<typeof captionSentenceSchema>;
const projectFields = { ...sharedProjectFields, captionSentences: z.array(captionSentenceSchema).min(1).max(2).optional(), captionReviewRequired: z.boolean().default(true) };
const currentProjectSchema = z.object({ version: z.literal(4), ...projectFields, words: z.array(currentWordSchema).max(20) });
const versionTwoProjectSchema = z.object({ version: z.literal(2), ...legacyProjectFields, words: z.array(currentWordSchema).max(20) });
const legacyProjectSchema = z.object({ version: z.literal(1), ...legacyProjectFields, words: z.array(legacyWordSchema).max(20) });
export const projectSchema = z.preprocess(input => {
    if (input && typeof input === 'object' && 'version' in input && input.version === 3) return { ...input, version: 4 };
    const versionTwo = versionTwoProjectSchema.safeParse(input);
    if (versionTwo.success) return migrateOldProject(versionTwo.data);
    const legacy = legacyProjectSchema.safeParse(input);
    if (!legacy.success) return input;
    const words = legacy.data.words.map(({ x, y, targetX, targetY, ...word }) => ({
        ...word, box: { x: targetX, y: targetY, width: 0, height: 0 }, labelCenterOverride: { x, y }, targetCenterOverride: { x: targetX, y: targetY },
    }));
    return migrateOldProject({ ...legacy.data, version: 2 as const, words });
}, currentProjectSchema).transform(syncCaption).superRefine((p, ctx) => {
    if (new Set(p.words.map(w => w.id)).size !== p.words.length) ctx.addIssue({ code: 'custom', message: '单词 ID 不能重复' });
    if (p.words.some(w => (w.kind ?? 'object') === 'object' && !w.box && !w.needsLocation)) ctx.addIssue({ code: 'custom', message: '物体词需要定位或标记待定位' });
});
export const wordSchema = currentWordSchema;
export type Word = z.infer<typeof wordSchema>;
export type Project = z.infer<typeof projectSchema>;
export function objectWords(words: Word[]) {
    return words.filter((w): w is Word & { box: NonNullable<Word['box']> } => (w.kind ?? 'object') === 'object' && !!w.box && !w.needsLocation);
}
export function sceneWords(words: Word[]) { return words.filter(w => w.kind === 'action' || w.kind === 'state'); }
export function readingWords(words: Word[]) { return [...words.filter(w => (w.kind ?? 'object') === 'object'), ...sceneWords(words)]; }
export const FPS = 30;
export const AUDIO_LEAD_FRAMES = 6;
export const AUDIO_TAIL_FRAMES = 9;
export const CAPTION_FRAMES = 90;
export const emptyProject: Project = {
    analysisMode: 'scene', sceneContext: '',
    version: 4, title: '生活里的英语', caption: '', captionChinese: '', captionReviewRequired: true, videoTemplate: 'direct', voiceId: 'English_Graceful_Lady', speechSpeed: 0.92,
    safeTop: 120, safeBottom: 240, safeRight: 0, imageWidth: 4, imageHeight: 3,
    captureSeconds: 2, introSeconds: 2, directIntroSeconds: .5, pauseSeconds: 1.2, words: [],
};
export function syncCaption<T extends { caption: string; captionChinese: string; captionSentences?: CaptionSentence[] }>(p: T): T {
    return p.captionSentences ? { ...p, caption: p.captionSentences.map(s => s.english).join(' '), captionChinese: p.captionSentences.map(s => s.chinese).join('') } : p;
}
export function descriptionSentences(p: Project): CaptionSentence[] {
    return p.captionSentences ?? [{ english: p.caption, chinese: p.captionChinese, audio: p.captionAudio, audioSeconds: p.captionAudioSeconds }];
}
export function editCaptionSentence(p: Project, index: number, patch: Pick<Partial<CaptionSentence>, 'english' | 'chinese'>): Project {
    return syncCaption({ ...p, captionSentences: descriptionSentences(p).map((sentence, i) => ({ ...sentence, ...(i === index ? patch : {}), audio: undefined, audioSeconds: undefined })), captionReviewRequired: true, captionAudio: undefined, captionAudioSeconds: undefined, socialCopy: undefined });
}
export function clearProjectSpeech(p: Project): Project {
    return { ...p, captionAudio: undefined, captionAudioSeconds: undefined,
        captionSentences: p.captionSentences?.map(({ audio, audioSeconds, ...sentence }) => sentence),
        words: p.words.map(({ audio, audioSeconds, ...word }) => word),
        interaction: p.interaction && { ...p.interaction, audio: undefined, audioSeconds: undefined },
    };
}
export function timeline(p: Project) {
    const intro = p.videoTemplate === 'direct' ? Math.round(p.directIntroSeconds * FPS) : Math.round(p.introSeconds * FPS);
    const reveal = p.videoTemplate === 'direct' ? 0 : 45;
    let cursor = intro + reveal;
    const words = readingWords(p.words).map(word => {
        const from = cursor;
        const audioFrames = Math.ceil((word.audioSeconds ?? 1) * FPS);
        const pauseFrames = Math.ceil(p.pauseSeconds * FPS);
        const duration = AUDIO_LEAD_FRAMES + audioFrames + AUDIO_TAIL_FRAMES + pauseFrames;
        cursor += duration;
        return { word, from, duration, audioFrames };
    });
    const captionFrom = cursor;
    const captions = descriptionSentences(p).map(sentence => {
        const from = cursor;
        const audioFrames = Math.ceil((sentence.audioSeconds ?? 0) * FPS);
        const duration = Math.max(CAPTION_FRAMES, AUDIO_LEAD_FRAMES + audioFrames + AUDIO_TAIL_FRAMES);
        cursor += duration;
        return { sentence, from, duration, audioFrames };
    });
    const captionAudioFrames = captions.reduce((sum, item) => sum + item.audioFrames, 0);
    const caption = cursor - captionFrom;
    const interactionFrom = captionFrom + caption;
    const interactionAudioFrames = Math.ceil((p.interaction?.audioSeconds ?? 0) * FPS);
    const interaction = p.interaction?.enabled ? Math.max(CAPTION_FRAMES, AUDIO_LEAD_FRAMES + interactionAudioFrames + AUDIO_TAIL_FRAMES) : 0;
    return { intro, reveal, words, captions, captionFrom, caption, captionAudioFrames, interactionFrom, interactionAudioFrames, interaction, total: interactionFrom + interaction };
}
export function activeWord(p: Project, frame: number) {
    return timeline(p).words.find(w => frame >= w.from && frame < w.from + w.duration)?.word;
}
export function changeEnglish(word: Word, english: string): Word {
    return { ...word, english, audio: undefined, audioSeconds: undefined };
}
export function exportReady(p: Project) {
    return exportBlockers(p).length === 0;
}
export function exportBlockers(p: Project): string[] {
    const blockers: string[] = [];
    if (!p.image) blockers.push('缺少照片');
    if (p.words.some(w => (w.kind ?? 'object') === 'object' && (!w.box || w.needsLocation))) blockers.push('物体词需要完成定位');
    if (p.interaction?.enabled) {
        if (!p.interaction.english.trim()) blockers.push('缺少互动句');
        else if (!p.interaction.audio || !p.interaction.audioSeconds) blockers.push('互动句尚未生成配音');
    }
    if (!p.words.length) blockers.push('缺少单词');
    else {
        const unnamed = p.words.filter(word => !word.english.trim()).length;
        const silent = p.words.filter(word => word.english.trim() && (!word.audio || !word.audioSeconds)).length;
        if (unnamed) blockers.push(`${unnamed} 个单词缺少英文`);
        if (silent) blockers.push(`${silent} 个单词尚未生成配音`);
    }
    if (!p.caption.trim()) blockers.push('缺少照片英文描述');
    else if (descriptionSentences(p).some(s => !s.english.trim() || (p.captionSentences && !s.chinese.trim()) || !s.audio || !s.audioSeconds)) blockers.push('照片句子尚未生成配音');
    return blockers;
}

function migrateOldProject(p: z.infer<typeof versionTwoProjectSchema>) {
    return {
        ...p,
        version: 4 as const,
        captionReviewRequired: !p.caption.trim(),
    };
}

export function openingMedia(p: Project) {
    const intro = timeline(p).intro;
    const capture = Math.round(p.captureSeconds * FPS);
    return { holdFrames: Math.max(0, intro - capture), startFrom: Math.max(0, capture - intro), playFrames: Math.min(intro, capture) };
}
export function sortByPhotoPosition<T extends { box: { x: number; y: number; width: number; height: number } }>(objects: T[]): T[] {
    return [...objects].sort((a, b) => {
        const centerAY = a.box.y + a.box.height / 2, centerBY = b.box.y + b.box.height / 2;
        const rowA = Math.round(centerAY / 0.08), rowB = Math.round(centerBY / 0.08);
        if (rowA !== rowB) return rowA - rowB;
        const horizontal = (a.box.x + a.box.width / 2) - (b.box.x + b.box.width / 2);
        return horizontal || centerAY - centerBY;
    });
}
