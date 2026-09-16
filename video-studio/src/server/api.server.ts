import { coverExportReady } from '../lib/cover-layout.ts';
import 'dotenv/config';
import { mkdir, readFile, writeFile, stat, rename, unlink } from 'node:fs/promises';
import { createReadStream, existsSync } from 'node:fs';
import { Readable } from 'node:stream';
import { resolve, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { z } from 'zod';
import { bundle } from '@remotion/bundler';
import { renderMedia, renderStill, selectComposition } from '@remotion/renderer';
import { getImageDimensions } from '../../../server/src/utils/image-dimensions.ts';
import { projectSchema, exportReady, timeline, voiceIdSchema, type Project } from '../lib/project.ts';
import { analyzeScene, generateCaptionVariants, generateSocialCopy, recognizeImage } from './recognition.server.ts';
import { learningPost } from '../lib/learning-post.ts';

const exec = promisify(execFile);
const root = resolve(process.env.STUDIO_DATA_DIR || '.data');
const assets = join(root, 'assets');
const exportsDir = join(root, 'exports');
const localChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browserExecutable = process.env.STUDIO_BROWSER_PATH || (existsSync(localChrome) ? localChrome : undefined);
const runtime = globalThis as typeof globalThis & { kakawordStudioJobs?: {
    jobs: Map<string, { status: string; progress: number; error?: string; file?: string }>;
    rendering: boolean; speechBusy: boolean;
} };
const state = runtime.kakawordStudioJobs ??= { jobs: new Map(), rendering: false, speechBusy: false };

function send(data: unknown, status = 200) {
    return Response.json(data, { status, headers: { 'Cache-Control': 'no-store' } });
}
async function body(req: Request, limit = 100 * 1024 * 1024) {
    if (Number(req.headers.get('content-length')) > limit) throw new Error('素材过大，请使用 100 MB 以内的文件');
    const reader = req.body?.getReader();
    if (!reader) return Buffer.alloc(0);
    const chunks: Uint8Array[] = []; let size = 0;
    try {
        while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            size += value.length;
            if (size > limit) { await reader.cancel(); throw new Error('素材过大，请使用 100 MB 以内的文件'); }
            chunks.push(value);
        }
    } finally { reader.releaseLock(); }
    return Buffer.concat(chunks);
}
async function json(req: Request) { return JSON.parse((await body(req, 2 * 1024 * 1024)).toString()); }
function assetFile(url: string) {
    const match = /^\/studio-api\/assets\/([a-f0-9-]+\.(?:jpg|mp4|mov|webm|wav))$/.exec(url);
    if (!match) throw new Error('无效素材路径');
    return join(assets, match[1]);
}
async function serveFile(req: Request, path: string, download = false): Promise<Response> {
    const info = await stat(path);
    const types: Record<string, string> = { jpg: 'image/jpeg', png: 'image/png', mp4: 'video/mp4', mov: 'video/quicktime', webm: 'video/webm', wav: 'audio/wav' };
    const headers: Record<string, string> = { 'Content-Type': types[path.split('.').pop()!] || 'application/octet-stream', 'Accept-Ranges': 'bytes', 'Cache-Control': 'no-store' };
    if (download) headers['Content-Disposition'] = `attachment; filename="kakaword.${path.endsWith('.png') ? 'png' : 'mp4'}"`;
    const range = req.headers.get('range');
    if (range) {
        const m = /^bytes=(\d+)-(\d*)$/.exec(range);
        const start = m ? Number(m[1]) : -1;
        const end = m?.[2] ? Math.min(Number(m[2]), info.size - 1) : info.size - 1;
        if (start < 0 || start > end) return new Response(null, { status: 416, headers: { 'Content-Range': `bytes */${info.size}` } });
        return new Response(Readable.toWeb(createReadStream(path, { start, end })) as ReadableStream<Uint8Array>, {
            status: 206, headers: { ...headers, 'Content-Range': `bytes ${start}-${end}/${info.size}`, 'Content-Length': String(end - start + 1) },
        });
    }
    return new Response(Readable.toWeb(createReadStream(path)) as ReadableStream<Uint8Array>, { headers: { ...headers, 'Content-Length': String(info.size) } });
}
function absoluteProject(p: Project, origin: string): Project {
    return { ...p, image: p.image && origin + p.image, video: p.video && origin + p.video,
        captionAudio: p.captionAudio && origin + p.captionAudio,
        interaction: p.interaction && { ...p.interaction, audio: p.interaction.audio && origin + p.interaction.audio },
        words: p.words.map(w => ({ ...w, audio: w.audio && origin + w.audio })) };
}
async function synthesizeSpeech(text: string, voiceId: string, speed: number, maxSeconds = 30) {
    const apiKey = process.env.MINIMAX_API_KEY?.trim();
    if (!apiKey) throw new Error('请在 video-studio/.env 配置 MINIMAX_API_KEY，然后重启网页服务');
    const controller = new AbortController(); const timeout = setTimeout(() => controller.abort(), 45000);
    let response: Response;
    try {
        response = await fetch('https://api.minimax.cn/v1/t2a_v2', {
            method: 'POST', signal: controller.signal,
            headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({
                model: process.env.MINIMAX_MODEL || 'speech-2.8-hd', text, stream: false, output_format: 'hex', language_boost: 'English',
                voice_setting: { voice_id: voiceId, speed, vol: 1, pitch: 0 },
                audio_setting: { sample_rate: 32000, bitrate: 128000, format: 'wav', channel: 1 },
                subtitle_enable: false,
            }),
        });
    } finally { clearTimeout(timeout); }
    const payload = await response.json() as { data?: { audio?: string; status?: number }; base_resp?: { status_code?: number; status_msg?: string } };
    if (!response.ok || payload.base_resp?.status_code !== 0 || !payload.data?.audio) throw new Error(`配音服务失败：${payload.base_resp?.status_msg || response.status}`);
    const id = randomUUID(); const wav = join(assets, `${id}.wav`);
    const audio = Buffer.from(payload.data.audio, 'hex');
    if (audio.length < 128) throw new Error('配音服务没有返回有效音频');
    await writeFile(wav, audio);
    const { stdout } = await exec('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', wav]);
    const audioSeconds = Number(stdout.trim());
    if (!Number.isFinite(audioSeconds) || audioSeconds <= 0 || audioSeconds > maxSeconds) throw new Error('无法生成有效配音，请检查 macOS 系统音色后重试');
    return { audio: `/studio-api/assets/${id}.wav`, audioSeconds };
}
async function render(id: string, p: Project, origin: string) {
    try {
        // Rebuild for each export so preview edits can never reuse an older film bundle.
        const serveUrl = await bundle({ entryPoint: resolve('src/video/Root.tsx') });
        const inputProps = { project: absoluteProject(p, origin) };
        const composition = await selectComposition({ serveUrl, id: 'Kakaword', inputProps, browserExecutable });
        await renderMedia({ composition, serveUrl, codec: 'h264', inputProps, browserExecutable,
            outputLocation: join(exportsDir, `${id}.mp4`), concurrency: 2,
            // Photo details and small type degrade badly with Remotion's default
            // H.264 settings. Render lossless intermediate frames and use a
            // visually high-quality CRF while retaining social-app compatible MP4.
            imageFormat: 'png', crf: 16, x264Preset: 'slow', pixelFormat: 'yuv420p', audioBitrate: '192k',
            onProgress: ({ progress }) => state.jobs.set(id, { status: 'rendering', progress }),
        });
        state.jobs.set(id, { status: 'complete', progress: 1, file: `/studio-api/exports/${id}.mp4` });
    } catch (error) {
        console.error('Video export failed:', error instanceof Error ? error.message : 'unknown error');
        state.jobs.set(id, { status: 'failed', progress: 0, error: '导出失败，请查看网页服务终端；检查浏览器渲染依赖和素材后重试。' });
    } finally { state.rendering = false; }
}

/** TanStack Start server route handler. No separate HTTP process or AI provider configuration. */
export async function handleStudioRequest(req: Request): Promise<Response> {
    try {
        const url = new URL(req.url);
        if (!['127.0.0.1', 'localhost'].includes(url.hostname)) return send({ error: '仅支持本地访问' }, 403);
        if (req.method !== 'GET' && req.headers.get('origin') && req.headers.get('origin') !== url.origin) return send({ error: '无效请求来源' }, 403);
        await Promise.all([mkdir(assets, { recursive: true }), mkdir(exportsDir, { recursive: true })]);
        const path = url.pathname;
        if (req.method === 'GET' && path.startsWith('/studio-api/assets/')) return await serveFile(req, assetFile(path));
        if (req.method === 'GET' && /^\/studio-api\/exports\/[a-f0-9-]+\.(?:mp4|png)$/.test(path)) return await serveFile(req, join(exportsDir, path.split('/').pop()!), true);
        if (req.method === 'GET' && path.startsWith('/studio-api/jobs/')) {
            const job = state.jobs.get(path.split('/').pop()!);
            return send(job || { error: '任务不存在，请重新导出' }, job ? 200 : 404);
        }
        if (req.method === 'GET' && path === '/studio-api/project') {
            const saved = await readFile(join(root, 'project.json'), 'utf8').catch(() => 'null');
            return send(JSON.parse(saved));
        }
        if (req.method === 'POST' && path === '/studio-api/project') {
            const p = projectSchema.parse(await json(req));
            const temp = join(root, `${randomUUID()}.json`);
            await writeFile(temp, JSON.stringify(p, null, 2)); await rename(temp, join(root, 'project.json'));
            return send({ saved: true });
        }
        if (req.method === 'POST' && path === '/studio-api/upload') {
            const ext = z.enum(['jpg', 'heic', 'heif', 'mp4', 'mov', 'webm']).parse(url.searchParams.get('ext'));
            const bytes = await body(req);
            if (!bytes.length) throw new Error('素材为空');
            if (ext === 'jpg' && !getImageDimensions(bytes)) throw new Error('无法读取图片');
            if (ext === 'heic' || ext === 'heif') {
                const id = randomUUID(); const source = join(root, `${id}.${ext}`); const output = join(assets, `${id}.jpg`);
                await writeFile(source, bytes);
                try { await exec(process.env.HEIF_CONVERT_PATH || 'heif-convert', [source, output], { timeout: 60000 }); }
                finally { await unlink(source).catch(() => undefined); }
                const jpeg = await readFile(output); const dimensions = getImageDimensions(jpeg);
                if (!dimensions) throw new Error('无法转换 Apple 动态照片');
                return send({ url: `/studio-api/assets/${id}.jpg`, imageWidth: dimensions.width, imageHeight: dimensions.height });
            }
            const name = `${randomUUID()}.${ext}`; await writeFile(join(assets, name), bytes);
            return send({ url: `/studio-api/assets/${name}` });
        }
        if (req.method === 'POST' && path === '/studio-api/scene') {
            const input = z.object({ image: z.string(), maxWords: z.number().int().min(4).max(10), context: z.string().max(500).default('') }).parse(await json(req));
            const bytes = await readFile(assetFile(input.image));
            if (!input.image.endsWith('.jpg') || !getImageDimensions(bytes)) throw new Error('请先选择有效照片');
            return send(await analyzeScene(bytes, input.maxWords, input.context, req.signal));
        }
        if (req.method === 'POST' && path === '/studio-api/analyze') {
            const { image, maxObjects } = z.object({ image: z.string(), maxObjects: z.number().int().min(3).max(10) }).parse(await json(req));
            if (!image.endsWith('.jpg')) throw new Error('请先选取照片帧');
            const bytes = await readFile(assetFile(image));
            if (!getImageDimensions(bytes)) throw new Error('无效图片');
            const recognitionResponse = await recognizeImage(bytes, maxObjects, req.signal);
            if (!recognitionResponse.ok) return recognitionResponse;
            const recognition = await recognitionResponse.json() as { caption: string; captionChinese: string; objects: { english: string; chinese: string }[] };
            const captionVariants = await generateCaptionVariants({
                caption: recognition.caption,
                captionChinese: recognition.captionChinese,
                words: recognition.objects.map(({ english, chinese }) => ({ english, chinese })),
            }, req.signal);
            return send({ ...recognition, captionVariants });
        }
        if (req.method === 'POST' && path === '/studio-api/speech') {
            if (state.speechBusy) return send({ error: '正在生成配音，请稍后重试' }, 409);
            const { words, caption, voiceId, speechSpeed, interaction } = z.object({
                interaction: z.string().trim().min(1).max(220).optional(),
                words: z.array(z.object({ id: z.string().max(80), english: z.string().trim().min(1).max(60) })).min(1).max(10),
                caption: z.string().trim().min(1).max(220),
                voiceId: voiceIdSchema,
                speechSpeed: z.number().min(0.5).max(2),
            }).parse(await json(req));
            state.speechBusy = true;
            try {
                const output = [];
                for (const word of words) {
                    output.push({ id: word.id, english: word.english, ...await synthesizeSpeech(word.english, voiceId, speechSpeed) });
                }
                const captionSpeech = await synthesizeSpeech(caption, voiceId, speechSpeed, 60);
                const interactionSpeech = interaction ? await synthesizeSpeech(interaction, voiceId, speechSpeed, 60) : undefined;
                return send({ words: output, captionAudio: captionSpeech.audio, captionAudioSeconds: captionSpeech.audioSeconds, interactionSpeech });
            } finally { state.speechBusy = false; }
        }
        if (req.method === 'POST' && path === '/studio-api/social-copy') {
            const p = projectSchema.parse(await json(req));
            const copy = await generateSocialCopy({
                sceneTheme: p.sceneTheme,
                interaction: p.interaction && { english: p.interaction.english, chinese: p.interaction.chinese },
                caption: p.caption,
                captionChinese: p.captionChinese,
                words: p.words.map(({ english, chinese, ipa, kind }) => ({ english, chinese, ipa, kind })),
                highlightedWords: p.words.filter(word => p.cover?.words[word.id]?.highlighted).map(word => word.english),
            }, req.signal);
            return send({ ...copy, xiaohongshu: { ...copy.xiaohongshu, body: learningPost(p) } });
        }
        if (req.method === 'POST' && path === '/studio-api/render') {
            const p = projectSchema.parse(await json(req));
            if (!exportReady(p)) throw new Error('请先添加照片、单词并生成全部配音');
            if (state.rendering) return send({ error: '已有导出正在进行，请等待完成' }, 409);
            await Promise.all([p.image!, p.captionAudio!, ...(p.interaction?.enabled ? [p.interaction.audio!] : []), ...(p.video ? [p.video] : []), ...p.words.map(w => w.audio!)].map(asset => stat(assetFile(asset))));
            const id = randomUUID(); state.rendering = true; state.jobs.set(id, { status: 'rendering', progress: 0 });
            void render(id, p, url.origin);
            return send({ id }, 202);
        }
        if (req.method === 'POST' && path === '/studio-api/render-cover') {
            const { project } = z.object({ project: projectSchema }).parse(await json(req));
            if (!coverExportReady(project)) throw new Error('请添加照片和单词，并解决封面胶囊冲突后再导出');
            await stat(assetFile(project.image!));
            const serveUrl = await bundle({ entryPoint: resolve('src/video/Root.tsx') });
            const inputProps = { project: absoluteProject(project, url.origin) };
            const composition = await selectComposition({ serveUrl, id: 'KakawordCover', inputProps, browserExecutable });
            const id = randomUUID();
            await renderStill({ composition, serveUrl, inputProps, browserExecutable, frame: 0, imageFormat: 'png', output: join(exportsDir, id + '.png') });
            return send({ file: '/studio-api/exports/' + id + '.png' });
        }
        if (req.method === 'POST' && path === '/studio-api/render-still') {
            const { project: rawProject, frame } = z.object({ project: z.unknown(), frame: z.number().int().min(0) }).parse(await json(req));
            const p = projectSchema.parse(rawProject);
            if (!p.image) throw new Error('请先添加照片');
            const boundedFrame = Math.min(frame, timeline(p).total - 1);
            await stat(assetFile(p.image));
            const serveUrl = await bundle({ entryPoint: resolve('src/video/Root.tsx') });
            const inputProps = { project: absoluteProject(p, url.origin) };
            const composition = await selectComposition({ serveUrl, id: 'Kakaword', inputProps, browserExecutable });
            const id = randomUUID(); const output = join(exportsDir, `${id}.png`);
            await renderStill({ composition, serveUrl, inputProps, browserExecutable, frame: boundedFrame, imageFormat: 'png', output });
            return send({ file: `/studio-api/exports/${id}.png`, frame: boundedFrame });
        }
        return send({ error: '接口不存在' }, 404);
    } catch (error) {
        const message = error instanceof Error ? error.message : '';
        const safe = /^(请|素材|无法|无效|单词|识别)/.test(message) ? message : '处理失败，请检查素材和网页服务终端。';
        console.error('Studio request failed:', error instanceof z.ZodError ? 'Invalid input' : error instanceof Error ? error.name : 'Unknown error');
        return send({ error: safe }, 400);
    }
}
