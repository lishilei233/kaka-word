import { randomUUID } from 'node:crypto';
import { studioSceneSchema } from '../../../server/src/core/image-analysis/studio-scene.ts';

export async function analyzeScene(bytes: Uint8Array, maxWords: number, context: string, signal?: AbortSignal, transport: typeof fetch = fetch) {
    const form = new FormData();
    form.set('image', new Blob([new Uint8Array(bytes)], { type: 'image/jpeg' }), 'photo.jpg');
    form.set('maxWords', String(maxWords)); form.set('context', context);
    const response = await transport(`${(process.env.SERVER_API_URL || 'http://127.0.0.1:8787').replace(/\/+$/, '')}/v1/studio/scene`, {
        method: 'POST', body: form, redirect: 'error', headers: { Authorization: `Bearer ${process.env.SERVER_ACCESS_TOKEN ?? ''}` },
        signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(120000)]) : AbortSignal.timeout(120000),
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.message || '场景分析失败');
    return studioSceneSchema.parse(result);
}
import { analyzeResultSchema } from '../../../server/src/core/image-analysis/types.ts';
import { captionVariantsSchema, socialCopySchema, type CaptionVariantsInput, type SocialCopyInput } from '../../../server/src/core/image-analysis/types.ts';
import { readSSEData } from '../../../server/src/core/image-analysis/streaming-json.ts';

export type RecognitionConnection = { baseURL: string; accessToken?: string; deviceToken?: string };

/** Transport adapter for the existing server API. AI credentials never enter this process. */
export async function forwardRecognition(
    bytes: Uint8Array,
    maxObjects: number,
    connection: RecognitionConnection,
    signal?: AbortSignal,
    transport: typeof fetch = fetch,
): Promise<Response> {
    const form = new FormData();
    form.set('image', new Blob([new Uint8Array(bytes)], { type: 'image/jpeg' }), 'photo.jpg');
    form.set('maxObjects', String(maxObjects));
    form.set('captionStyle', 'serious');
    form.set('language', 'zh-CN');
    const headers = new Headers({ 'X-Operation-ID': randomUUID(), Accept: 'text/event-stream' });
    if (connection.accessToken) headers.set('Authorization', `Bearer ${connection.accessToken}`);
    if (connection.deviceToken) headers.set('X-DeviceCheck-Token', connection.deviceToken);
    const timeout = AbortSignal.timeout(120000);
    let response: Response;
    try {
        response = await transport(`${connection.baseURL.replace(/\/+$/, '')}/v1/analyze`, {
            method: 'POST', body: form, headers, redirect: 'error',
            signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
        });
    } catch {
        return Response.json({ error: 'SERVER_UNAVAILABLE', message: '无法连接现有识别服务，请检查 server 是否运行及接口地址。' }, { status: 502 });
    }
    if (!response.ok) {
        const error = await response.json().catch(() => ({})) as { error?: string; message?: string };
        return Response.json({ error: error.error || 'SERVER_ERROR', message: error.message || `识别服务返回 ${response.status}` }, {
            status: response.status,
            headers: response.headers.has('retry-after') ? { 'Retry-After': response.headers.get('retry-after')! } : undefined,
        });
    }
    if (response.headers.get('content-type')?.includes('text/event-stream')) {
        if (!response.body) throw new Error('识别服务没有返回数据');
        let result: unknown;
        for await (const data of readSSEData(response.body)) {
            const event = JSON.parse(data) as Record<string, unknown>;
            if (event.error) return Response.json({ error: event.error, message: typeof event.message === 'string' ? event.message : '识别服务暂时失败，请重试。' }, { status: 502 });
            if (Array.isArray(event.objects)) result = event;
        }
        if (!result) throw new Error('识别响应中断，未收到完整结果，请重试');
        return Response.json(analyzeResultSchema.parse(result));
    }
    return Response.json(analyzeResultSchema.parse(await response.json()));
}

export function recognizeImage(bytes: Uint8Array, maxObjects: number, signal?: AbortSignal) {
    return forwardRecognition(bytes, maxObjects, {
        baseURL: process.env.SERVER_API_URL || 'http://127.0.0.1:8787',
        accessToken: process.env.SERVER_ACCESS_TOKEN,
        deviceToken: process.env.SERVER_DEVICE_TOKEN,
    }, signal);
}

export async function generateSocialCopy(input: SocialCopyInput, signal?: AbortSignal, transport: typeof fetch = fetch) {
    const baseURL = (process.env.SERVER_API_URL || 'http://127.0.0.1:8787').replace(/\/+$/, '');
    const headers = new Headers({ 'Content-Type': 'application/json', 'X-Operation-ID': randomUUID() });
    if (process.env.SERVER_ACCESS_TOKEN) headers.set('Authorization', `Bearer ${process.env.SERVER_ACCESS_TOKEN}`);
    let response: Response;
    try {
        response = await transport(`${baseURL}/v1/social-copy`, { method: 'POST', headers, body: JSON.stringify(input), signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(120000)]) : AbortSignal.timeout(120000) });
    } catch {
        throw new Error('无法连接现有 AI 服务，请检查 server 是否运行');
    }
    const result = await response.json().catch(() => ({})) as Record<string, unknown>;
    if (!response.ok) throw new Error(typeof result.message === 'string' ? result.message : '发布文案生成失败');
    return socialCopySchema.parse(result);
}

export async function generateCaptionVariants(input: CaptionVariantsInput, signal?: AbortSignal, transport: typeof fetch = fetch) {
    const baseURL = (process.env.SERVER_API_URL || 'http://127.0.0.1:8787').replace(/\/+$/, '');
    const headers = new Headers({ 'Content-Type': 'application/json', 'X-Operation-ID': randomUUID() });
    if (process.env.SERVER_ACCESS_TOKEN) headers.set('Authorization', `Bearer ${process.env.SERVER_ACCESS_TOKEN}`);
    let response: Response;
    try {
        response = await transport(`${baseURL}/v1/caption-variants`, { method: 'POST', headers, body: JSON.stringify(input), signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(120000)]) : AbortSignal.timeout(120000) });
    } catch {
        throw new Error('无法连接现有 AI 服务，请检查 server 是否运行');
    }
    const result = await response.json().catch(() => ({})) as Record<string, unknown>;
    if (!response.ok) throw new Error(typeof result.message === 'string' ? result.message : '多版本照片描述生成失败');
    return captionVariantsSchema.parse(result);
}
