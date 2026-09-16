export async function api<T>(path: string, data?: unknown): Promise<T> {
    const response = await fetch(`/studio-api/${path}`, data === undefined ? undefined : { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
    const result = await response.json().catch(() => ({ error: '网页服务返回异常，请检查 npm run dev 终端' }));
    if (!response.ok || (result && typeof result === 'object' && 'error' in result)) {
        const failure = result && typeof result === 'object' ? result as { message?: string; error?: string } : {};
        throw new Error(failure.message || failure.error || '请求失败');
    }
    return result;
}
export async function upload(blob: Blob, ext: string) {
    const response = await fetch(`/studio-api/upload?ext=${ext}`, { method: 'POST', body: blob });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || '上传失败');
    return result.url as string;
}
export async function uploadApplePhoto(blob: Blob, ext: 'heic' | 'heif') {
    const response = await fetch(`/studio-api/upload?ext=${ext}`, { method: 'POST', body: blob });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || 'Apple 照片转换失败');
    return result as { url: string; imageWidth: number; imageHeight: number };
}
export async function snapshot(source: HTMLImageElement | HTMLVideoElement) {
    const width = source instanceof HTMLVideoElement ? source.videoWidth : source.naturalWidth;
    const height = source instanceof HTMLVideoElement ? source.videoHeight : source.naturalHeight;
    if (!width || !height) throw new Error('素材尚未加载完成');
    const scale = Math.min(1, 1800 / Math.max(width, height));
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(width * scale); canvas.height = Math.round(height * scale);
    canvas.getContext('2d')!.drawImage(source, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise<Blob>((resolve, reject) => canvas.toBlob(b => b ? resolve(b) : reject(new Error('无法生成照片')), 'image/jpeg', .93));
    return { image: await upload(blob, 'jpg'), imageWidth: canvas.width, imageHeight: canvas.height };
}
