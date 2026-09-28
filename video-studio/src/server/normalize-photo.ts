import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const exec = promisify(execFile);

// Bake EXIF rotation into pixels so browsers and vision providers see the same axes.
export async function normalizedPhoto(path: string): Promise<Buffer> {
    const directory = await mkdtemp(join(tmpdir(), 'studio-photo-'));
    try {
        const output = join(directory, 'photo.jpg');
        await exec('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-i', path,
            '-frames:v', '1', '-vf', "scale=w='min(1800,iw)':h='min(1800,ih)':force_original_aspect_ratio=decrease",
            '-q:v', '2', '-map_metadata', '-1', output], { timeout: 60000 });
        return await readFile(output);
    } finally {
        await rm(directory, { recursive: true, force: true });
    }
}
