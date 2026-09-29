import { mkdir, readFile, writeFile, rename, readdir, unlink } from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { getImageDimensions } from './image-dimensions';
import { emptyProject, projectSchema } from '../lib/project';
import { projectContentSchema, projectRecordSchema, type ProjectContent, type ProjectRecord, type ProjectSummary } from '../lib/project-record';

export class ProjectError extends Error {
    constructor(message: string, public status: number) { super(message); }
}
export class ProjectStore {
    private queues = new Map<string, Promise<unknown>>();
    private initialized?: Promise<void>;
    constructor(private root: string) {}
    private async serial<T>(id: string, work: () => Promise<T>): Promise<T> {
        const next = (this.queues.get(id) ?? Promise.resolve()).catch(() => {}).then(work);
        this.queues.set(id, next);
        try { return await next; } finally { if (this.queues.get(id) === next) this.queues.delete(id); }
    }
    private path(id: string) {
        if (!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(id)) throw new ProjectError('无效作品编号', 400);
        return join(this.root, 'projects', `${id}.json`);
    }
    private async atomic(path: string, data: unknown) {
        const temp = `${path}.${randomUUID()}.tmp`;
        try { await writeFile(temp, JSON.stringify(data, null, 2)); await rename(temp, path); }
        finally { await unlink(temp).catch(() => {}); }
    }
    async init() {
        this.initialized ??= this.migrate().catch(error => { this.initialized = undefined; throw error; });
        return this.initialized;
    }
    private async migrate() {
        await mkdir(join(this.root, 'projects'), { recursive: true });
        const marker = join(this.root, 'projects-migration.json');
        try { await readFile(marker); return; } catch (e) { if ((e as NodeJS.ErrnoException).code !== 'ENOENT') throw e; }
        let legacy: string;
        try { legacy = await readFile(join(this.root, 'project.json'), 'utf8'); }
        catch (e) { if ((e as NodeJS.ErrnoException).code !== 'ENOENT') throw e; await this.atomic(marker, { complete: true }); return; }
        try {
            const raw = JSON.parse(legacy);
            if (raw !== null) {
                const project = projectSchema.parse(raw);
                if (project.image) {
                    const dimensions = await readFile(join(this.root, 'assets', project.image.split('/').pop()!)).then(getImageDimensions).catch(() => null);
                    if (dimensions) { project.imageWidth = dimensions.width; project.imageHeight = dimensions.height; }
                }
                // Stable ID makes interrupted migrations idempotent, even before the marker is written.
                const id = '00000000-0000-4000-8000-000000000001';
                const now = new Date().toISOString();
                try { await readFile(this.path(id)); }
                catch (e) {
                    if ((e as NodeJS.ErrnoException).code !== 'ENOENT') throw e;
                    await this.atomic(this.path(id), { id, createdAt: now, updatedAt: now, revision: 0, project, editor: { source: project.video ?? '', pendingLivePhotoVideo: '' } });
                }
            }
            await this.atomic(marker, { complete: true });
        } catch { throw new ProjectError('旧草稿迁移失败，请检查 project.json；原文件已保留。', 500); }
    }
    async get(id: string): Promise<ProjectRecord> {
        await this.init();
        try { return projectRecordSchema.parse(JSON.parse(await readFile(this.path(id), 'utf8'))); }
        catch (e) { if ((e as NodeJS.ErrnoException).code === 'ENOENT') throw new ProjectError('作品不存在或已删除', 404); throw e; }
    }
    async list(): Promise<ProjectSummary[]> {
        await this.init();
        const records = await Promise.all((await readdir(join(this.root, 'projects'))).filter(name => name.endsWith('.json')).map(async name => {
            try { return await this.get(name.slice(0, -5)); } catch (e) { if (e instanceof ProjectError && e.status === 404) return null; throw e; }
        }));
        return records.filter((r): r is ProjectRecord => !!r).sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)).map(({ id, createdAt, updatedAt, revision, project }) => ({ id, createdAt, updatedAt, revision, title: project.title, image: project.image }));
    }
    async create(content?: ProjectContent) {
        await this.init();
        const value = projectContentSchema.parse(content ?? { project: { ...emptyProject, title: '未命名视频' }, editor: { source: '', pendingLivePhotoVideo: '' } });
        const now = new Date().toISOString();
        const record: ProjectRecord = { ...value, id: randomUUID(), createdAt: now, updatedAt: now, revision: 0 };
        await this.atomic(this.path(record.id), record);
        return record;
    }
    async update(id: string, revision: number, content: ProjectContent) {
        await this.init();
        return this.serial(id, async () => {
            const old = await this.get(id);
            if (old.revision !== revision) throw new ProjectError('此作品已在其他页面修改，请重新加载或另存为新作品。', 409);
            const record = { ...old, ...projectContentSchema.parse(content), revision: old.revision + 1, updatedAt: new Date().toISOString() };
            await this.atomic(this.path(id), record);
            return record;
        });
    }
    async remove(id: string, revision: number) {
        await this.init();
        return this.serial(id, async () => {
            const old = await this.get(id);
            if (old.revision !== revision) throw new ProjectError('作品已更新，请刷新列表后再删除。', 409);
            await unlink(this.path(id));
        });
    }
    async copy(id: string) {
        const old = await this.get(id);
        return this.create({ project: { ...old.project, title: `${old.project.title} 副本`.slice(0, 80) }, editor: old.editor });
    }
}
