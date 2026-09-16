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
        const image = form?.get('image'), context = form?.get('context') ?? '', maxWords = Number(form?.get('maxWords'));
        if (!(image instanceof File) || typeof context !== 'string' || context.length > 500 || !Number.isInteger(maxWords) || maxWords < 4 || maxWords > 10 || image.size > 10 * 1024 * 1024) return c.json({ message: '请提供有效照片、背景说明及 4～10 的词数上限' }, 400);
        const bytes = new Uint8Array(await image.arrayBuffer());
        if (!getImageDimensions(bytes) || image.type !== 'image/jpeg') return c.json({ message: '请提供 JPEG 照片' }, 400);
        try {
            const result = studioSceneSchema.parse(await dependencies.provider.analyzeStudioScene({ image: bytes, mimeType: 'image/jpeg', context, maxWords, signal: AbortSignal.any([c.req.raw.signal, AbortSignal.timeout(120000)]) }));
            return c.json({ ...result, words: result.words.slice(0, maxWords) });
        } catch { return c.json({ message: '场景分析失败，请重试或切换物体识别' }, 502); }
    });
}
