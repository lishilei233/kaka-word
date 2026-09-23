import { z } from "zod";

export const objectBoxSchema = z.object({
  x: z.number().min(0).max(1),
  y: z.number().min(0).max(1),
  width: z.number().min(0).max(1),
  height: z.number().min(0).max(1),
});

export const objectAnchorSchema = z.object({
  x: z.number().min(0).max(1),
  y: z.number().min(0).max(1),
});

export const objectCandidateSchema = z.object({
  english: z.string().min(1).max(60),
  chinese: z.string().min(1).max(60),
  ipa: z.string().max(80).default(""),
  example: z.string().min(1).max(180),
  exampleChinese: z.string().min(1).max(180).optional(),
});

export const confirmationStatusSchema = z.enum(["confirmed", "needsConfirmation", "userConfirmed"]);

export const learningObjectSchema = z.object({
  id: z.string().min(1).max(40),
  english: z.string().min(1).max(60),
  chinese: z.string().min(1).max(60),
  ipa: z.string().max(80).default(""),
  confidence: z.number().min(0).max(1),
  box: objectBoxSchema,
  anchor: objectAnchorSchema.optional().catch(undefined),
  anchorSource: z.enum(["ai", "centerFallback", "manual"]).optional(),
  anchorNeedsReview: z.boolean().optional(),
  example: z.string().min(1).max(180),
  exampleChinese: z.string().min(1).max(180).optional(),
  candidates: z.array(objectCandidateSchema).min(2).max(3).optional(),
  confirmationStatus: confirmationStatusSchema.default("confirmed"),
});

export const sceneWordKindSchema = z.enum(["action", "state"]);

export const sceneWordSchema = z.object({
  id: z.string().min(1).max(40),
  kind: sceneWordKindSchema,
  english: z.string().min(1).max(60),
  chinese: z.string().min(1).max(60),
  ipa: z.string().max(80).default(""),
  example: z.string().min(1).max(180),
  exampleChinese: z.string().min(1).max(180).optional(),
});

export const captionStyleSchema = z.enum(["serious", "funny"]);

export const requestedCaptionStyleSchema = z.enum(["serious", "funny", "random"]);

export const vocabularyDetailsSchema = z.object({
  english: z.string().min(1).max(60),
  chinese: z.string().min(1).max(60),
  ipa: z.string().max(80).default(""),
  example: z.string().min(1).max(180),
  exampleChinese: z.string().min(1).max(180).optional(),
});

export const analyzeResultSchema = z.object({
  imageWidth: z.number().int().positive(),
  imageHeight: z.number().int().positive(),
  objects: z.array(learningObjectSchema).max(10),
  sceneWords: z.array(sceneWordSchema).max(5).default([]),
  caption: z.string().min(1).max(220),
  captionChinese: z.string().min(1).max(220),
  captionStyle: captionStyleSchema,
});

export const providerAnalyzeResultSchema = analyzeResultSchema.omit({ captionStyle: true });

export type AnalyzeResult = z.infer<typeof analyzeResultSchema>;
export type SceneWord = z.infer<typeof sceneWordSchema>;
export type CaptionStyle = z.infer<typeof captionStyleSchema>;
export type RequestedCaptionStyle = z.infer<typeof requestedCaptionStyleSchema>;
export type VocabularyDetails = z.infer<typeof vocabularyDetailsSchema>;
export type ConfirmationStatus = z.infer<typeof confirmationStatusSchema>;

export type VisionInput = {
  image: Uint8Array;
  mimeType: string;
  imageWidth: number;
  imageHeight: number;
  language: "zh-CN";
  maxObjects: number;
  captionStyle: CaptionStyle;
  masteredWords: string[];
  signal?: AbortSignal;
};

export type VocabularyInput = {
  term: string;
  kind?: "object" | "action" | "state";
  language: "zh-CN";
  signal?: AbortSignal;
};

export const socialPostSchema = z.object({
  title: z.string().min(1).max(80),
  body: z.string().min(1).max(1000),
  hashtags: z.array(z.string().min(1).max(40)).max(12),
});
export const socialCopySchema = z.object({
  xiaohongshu: socialPostSchema,
  douyin: socialPostSchema,
  channels: socialPostSchema,
});
export type SocialCopy = z.infer<typeof socialCopySchema>;
export type SocialCopyInput = {
  sceneTheme?: string;
  interaction?: { english: string; chinese: string };
  caption: string;
  captionChinese: string;
  words: { english: string; chinese: string; ipa?: string; kind?: 'object' | 'action' | 'state' }[];
  highlightedWords: string[];
  signal?: AbortSignal;
};
export const photoCaptionSchema = z.object({
  caption: z.string().trim().min(1).max(220),
  captionChinese: z.string().trim().min(1).max(220),
});
export type PhotoCaption = z.infer<typeof photoCaptionSchema>;
export type CaptionGenerationInput = {
  image: Uint8Array;
  mimeType: string;
  words: { english: string; chinese: string; kind?: 'object' | 'action' | 'state' }[];
  context?: string;
  signal?: AbortSignal;
};
export type CaptionReviewInput = {
  image: Uint8Array;
  mimeType: string;
  caption: string;
  captionChinese: string;
  words: { english: string; chinese: string; kind?: 'object' | 'action' | 'state' }[];
  context?: string;
  signal?: AbortSignal;
};

export interface VisionProvider {
  analyzeStudioScene?(input: import('./studio-scene.js').StudioSceneInput): Promise<import('./studio-scene.js').StudioScene>;
  generateCaption?(input: CaptionGenerationInput): Promise<PhotoCaption>;
  reviewCaption?(input: CaptionReviewInput): Promise<PhotoCaption>;
  analyze(input: VisionInput): Promise<AnalyzeResult>;
  analyzeStream?(
    input: VisionInput,
    onObject: (object: AnalyzeResult["objects"][number]) => Promise<void> | void,
  ): Promise<AnalyzeResult>;
  resolveVocabulary(input: VocabularyInput): Promise<VocabularyDetails>;
  generateSocialCopy?(input: SocialCopyInput): Promise<SocialCopy>;
}
