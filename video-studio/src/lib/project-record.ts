import { z } from 'zod';
import { projectSchema } from './project';

const videoSource = z.string().regex(/^\/studio-api\/assets\/[a-f0-9-]+\.(mp4|mov|webm)$/);
export const editorStateSchema = z.object({
    source: videoSource.or(z.literal('')).default(''),
    pendingLivePhotoVideo: videoSource.or(z.literal('')).default(''),
});
export const projectContentSchema = z.object({ project: projectSchema, editor: editorStateSchema });
export const projectRecordSchema = projectContentSchema.extend({
    id: z.string().uuid(), createdAt: z.string(), updatedAt: z.string(), revision: z.number().int().nonnegative(),
});
export type ProjectContent = z.infer<typeof projectContentSchema>;
export type ProjectRecord = z.infer<typeof projectRecordSchema>;
export type ProjectSummary = Pick<ProjectRecord, 'id' | 'createdAt' | 'updatedAt' | 'revision'> & { title: string; image?: string };
