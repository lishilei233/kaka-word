import type { Hono } from 'hono';
import type { AppEnv } from '../app.js';
import type { VisionProvider } from '../core/image-analysis/types.js';
import { studioSceneSchema } from '../core/image-analysis/studio-scene.js';
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
            return c.json(studioSceneSchema.parse({ ...scene, words: [...objects, ...sceneWords] }));
        } catch { return c.json({ message: '场景分析失败，请重试或切换物体识别' }, 502); }
    });
}
