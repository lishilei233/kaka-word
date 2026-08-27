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
export const learningObjectSchema = z.object({
    id: z.string().min(1).max(40),
    english: z.string().min(1).max(60),
    chinese: z.string().min(1).max(60),
    ipa: z.string().max(80).default(""),
    confidence: z.number().min(0).max(1),
    box: objectBoxSchema,
    anchor: objectAnchorSchema.optional(),
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
    objects: z.array(learningObjectSchema).max(8),
    caption: z.string().min(1).max(220),
    captionChinese: z.string().min(1).max(220),
    captionStyle: captionStyleSchema,
});
export const providerAnalyzeResultSchema = analyzeResultSchema.omit({ captionStyle: true });
