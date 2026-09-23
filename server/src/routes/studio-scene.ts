import type { Hono } from 'hono';
import { z } from 'zod';
import type { AppEnv } from '../app.js';
import type { VisionProvider } from '../core/image-analysis/types.js';
import { studioSceneSchema } from '../core/image-analysis/studio-scene.js';
import { photoCaptionSchema, normalizeCaption } from '../core/image-analysis/types.js';
import { authenticateVideoStudio, unauthorized } from './access-auth.js';
import { getImageDimensions } from '../utils/image-dimensions.js';

export function registerStudioSceneRoute(app: Hono<AppEnv>, dependencies: { provider: VisionProvider; videoStudioAccessToken?: string }) {
    app.post('/v1/studio/scene', async c => {
        if (!authenticateVideoStudio(c.req.header('authorization'), dependencies.videoStudioAccessToken)) return unauthorized(c);
        if (!dependencies.provider.analyzeStudioScene) return c.json({ message: '当前 AI 服务暂不支持场景分析，请切换物体识别' }, 503);
        const form = await c.req.formData().catch(() => null);
        const image = form?.get('image'), context = form?.get('context') ?? '', maxObjects = Number(form?.get('maxObjects'));
        if (!(image instanceof File) || typeof context !== 'string' || context.length > 500 || !Number.isInteger(maxObjects) || maxObjects < 3 || maxObjects > 10 || image.size > 10 * 1024 * 1024) return c.json({ message: '请提供有效照片、背景说明及 3～10 的物体数上限' }, 400);
        const bytes = new Uint8Array(await image.arrayBuffer());
        const dimensions = getImageDimensions(bytes);
        if (!dimensions || image.type !== 'image/jpeg') return c.json({ message: '请提供 JPEG 照片' }, 400);
        try {
            const signal = AbortSignal.any([c.req.raw.signal, AbortSignal.timeout(120000)]);
            const recognition = await dependencies.provider.analyze({
                image: bytes,
                mimeType: 'image/jpeg',
                imageWidth: dimensions.width,
                imageHeight: dimensions.height,
                language: 'zh-CN',
                maxObjects,
                captionStyle: 'serious',
                masteredWords: [],
                signal,
            });
            const objectIDs = new Set<string>();
            const objects = recognition.objects.slice(0, maxObjects).map((object, index) => {
                let id = object.id;
                let suffix = index + 1;
                while (objectIDs.has(id)) id = `object_${suffix++}`;
                objectIDs.add(id);
                return {
                    id,
                    kind: 'object' as const,
                    english: object.english,
                    chinese: object.chinese,
                    ipa: object.ipa,
                    box: object.box,
                };
            });
            const scene = studioSceneSchema.parse(await dependencies.provider.analyzeStudioScene({
                image: bytes,
                mimeType: 'image/jpeg',
                context,
                maxSceneWords: 10,
                objects: objects.map(({ english, chinese }) => ({ english, chinese })),
                signal,
            }));
            const usedIDs = new Set(objectIDs);
            const sceneWords = scene.words
                .filter(word => word.kind === 'action' || word.kind === 'state')
                .slice(0, 10)
                .map((word, index) => {
                    let id = word.id;
                    let suffix = index + 1;
                    while (usedIDs.has(id)) id = `scene_${suffix++}`;
                    usedIDs.add(id);
                    return { ...word, id };
                });
            if (!dependencies.provider.reviewCaption) throw new Error('Caption review is unavailable');
            const words = [...objects, ...sceneWords];
            const reviewed = await dependencies.provider.reviewCaption({
                image: bytes,
                mimeType: 'image/jpeg',
                context,
                caption: scene.caption,
                captionChinese: scene.captionChinese,
                words: words.map(({ english, chinese, kind }) => ({ english, chinese, kind })),
                signal,
            });
            return c.json(studioSceneSchema.parse({ ...scene, ...reviewed, captionSentences: reviewed.captionSentences, words }));
        } catch { return c.json({ message: '场景分析失败，请重试或切换物体识别' }, 502); }
    });

    app.post('/v1/studio/caption-review', async c => {
        if (!authenticateVideoStudio(c.req.header('authorization'), dependencies.videoStudioAccessToken)) return unauthorized(c);
        if (!dependencies.provider.reviewCaption) return c.json({ message: '当前 AI 服务暂不支持照片描述审校' }, 503);
        const form = await c.req.formData().catch(() => null);
        const image = form?.get('image');
        const caption = form?.get('caption');
        const captionChinese = form?.get('captionChinese');
        const context = form?.get('context') ?? '';
        const wordsJSON = form?.get('words');
        const wordsSchema = z.array(z.object({
            english: z.string().trim().min(1).max(60),
            chinese: z.string().max(60),
            kind: z.enum(['object', 'action', 'state']).optional(),
        })).max(20);
        let words: ReturnType<typeof wordsSchema.safeParse> | null = null;
        if (typeof wordsJSON === 'string') {
            try { words = wordsSchema.safeParse(JSON.parse(wordsJSON)); } catch { words = null; }
        }
        if (!(image instanceof File) || image.type !== 'image/jpeg' || image.size > 10 * 1024 * 1024
            || typeof caption !== 'string' || !caption.trim() || caption.length > 441
            || typeof captionChinese !== 'string' || captionChinese.length > 440
            || typeof context !== 'string' || context.length > 500 || !words?.success) {
            return c.json({ message: '请提供有效照片、描述和词表' }, 400);
        }
        const bytes = new Uint8Array(await image.arrayBuffer());
        if (!getImageDimensions(bytes)) return c.json({ message: '请提供有效 JPEG 照片' }, 400);
        try {
            const signal = AbortSignal.any([c.req.raw.signal, AbortSignal.timeout(120000)]);
            return c.json(normalizeCaption(photoCaptionSchema.parse(await dependencies.provider.reviewCaption({
                image: bytes, mimeType: 'image/jpeg', caption, captionChinese,
                context, words: words.data, signal,
            }))));
        } catch {
            return c.json({ message: '照片描述审校失败，原内容未改变，请重试' }, 502);
        }
    });

    app.post('/v1/studio/caption-regenerate', async c => {
        if (!authenticateVideoStudio(c.req.header('authorization'), dependencies.videoStudioAccessToken)) return unauthorized(c);
        if (!dependencies.provider.generateCaption || !dependencies.provider.reviewCaption) return c.json({ message: '当前 AI 服务暂不支持照片描述生成与审校' }, 503);
        const form = await c.req.formData().catch(() => null);
        const image = form?.get('image'), context = form?.get('context') ?? '', wordsJSON = form?.get('words');
        const wordsSchema = z.array(z.object({
            english: z.string().trim().min(1).max(60), chinese: z.string().max(60),
            kind: z.enum(['object', 'action', 'state']).optional(),
        })).min(1).max(20);
        let words: z.infer<typeof wordsSchema> | undefined;
        if (typeof wordsJSON === 'string') {
            try { words = wordsSchema.parse(JSON.parse(wordsJSON)); } catch { words = undefined; }
        }
        if (!(image instanceof File) || image.type !== 'image/jpeg' || image.size > 10 * 1024 * 1024
            || typeof context !== 'string' || context.length > 500 || !words) return c.json({ message: '请提供有效照片和当前词表' }, 400);
        const bytes = new Uint8Array(await image.arrayBuffer());
        if (!getImageDimensions(bytes)) return c.json({ message: '请提供有效 JPEG 照片' }, 400);
        try {
            const signal = AbortSignal.any([c.req.raw.signal, AbortSignal.timeout(120000)]);
            const draft = normalizeCaption(photoCaptionSchema.parse(await dependencies.provider.generateCaption({ image: bytes, mimeType: 'image/jpeg', words, context, signal })));
            const reviewed = await dependencies.provider.reviewCaption({ image: bytes, mimeType: 'image/jpeg', ...draft, words, context, signal });
            return c.json(normalizeCaption(photoCaptionSchema.parse(reviewed)));
        } catch {
            return c.json({ message: '照片描述生成或审校失败，原内容未改变，请重试' }, 502);
        }
    });
}
