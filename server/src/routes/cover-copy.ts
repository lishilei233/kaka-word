import type { Hono } from 'hono';
import type { AppEnv } from '../app.js';
import type { VisionProvider } from '../core/image-analysis/types.js';
import { coverCopyInputSchema, coverCopySchema } from '../core/image-analysis/cover-copy.js';
import { authenticateVideoStudio, unauthorized } from './access-auth.js';

export function registerCoverCopyRoute(app: Hono<AppEnv>, dependencies: { provider: VisionProvider; videoStudioAccessToken?: string }) {
    app.post('/v1/studio/cover-copy', async c => {
        if (!authenticateVideoStudio(c.req.header('authorization'), dependencies.videoStudioAccessToken)) return unauthorized(c);
        if (!dependencies.provider.generateCoverCopy) return c.json({ message: '当前 AI 服务暂不支持封面标题建议' }, 503);
        const input = coverCopyInputSchema.safeParse(await c.req.json().catch(() => null));
        if (!input.success) return c.json({ message: '请先准备照片描述和有效词表' }, 400);
        try {
            const signal = AbortSignal.any([c.req.raw.signal, AbortSignal.timeout(120000)]);
            const copy = await dependencies.provider.generateCoverCopy({ ...input.data, signal });
            signal.throwIfAborted();
            return c.json(coverCopySchema.parse(copy));
        } catch {
            return c.json({ message: '封面标题生成失败，原内容未改变，请重试' }, 502);
        }
    });
}
