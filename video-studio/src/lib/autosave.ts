import type { ProjectContent, ProjectRecord } from './project-record';

export type SaveStatus = 'saved' | 'pending' | 'saving' | 'error' | 'conflict';
type Clock = { set: (callback: () => void, ms: number) => unknown; clear: (timer: unknown) => void };
const realClock: Clock = { set: (fn, ms) => setTimeout(fn, ms), clear: timer => clearTimeout(timer as ReturnType<typeof setTimeout>) };

/** One writer per mounted editor. Revisions come only from acknowledged server writes. */
export class Autosave {
    status: SaveStatus = 'saved';
    error = '';
    private current: ProjectContent;
    private saved: string;
    private revision: number;
    private debounce?: unknown;
    private deadline?: unknown;
    private running?: Promise<boolean>;
    private disposed = false;
    constructor(record: ProjectRecord, private write: (revision: number, content: ProjectContent) => Promise<ProjectRecord>, private notify: () => void, private clock = realClock) {
        this.current = { project: record.project, editor: record.editor };
        this.saved = JSON.stringify(this.current);
        this.revision = record.revision;
    }
    get dirty() { return JSON.stringify(this.current) !== this.saved; }
    get content() { return this.current; }
    change(content: ProjectContent) {
        this.current = content;
        if (this.disposed || this.status === 'conflict') return;
        if (!this.dirty && !this.running) { this.cancelTimers(); this.status = 'saved'; this.notify(); return; }
        if (this.status === 'error') return; // Keep failures visible until explicit retry.
        if (!this.running) this.status = 'pending';
        this.clock.clear(this.debounce);
        this.debounce = this.clock.set(() => { void this.flush(); }, 1000);
        this.deadline ??= this.clock.set(() => { void this.flush(); }, 10000);
        this.notify();
    }
    private cancelTimers() {
        this.clock.clear(this.debounce); this.clock.clear(this.deadline);
        this.debounce = this.deadline = undefined;
    }
    async flush(): Promise<boolean> {
        this.cancelTimers();
        if (this.disposed || this.status === 'conflict') return false;
        if (this.running) return this.running;
        this.running = this.drain();
        try { return await this.running; } finally { this.running = undefined; }
    }
    private async drain() {
        while (this.dirty && !this.disposed) {
            const content = this.current;
            const serialized = JSON.stringify(content);
            this.status = 'saving'; this.error = ''; this.notify();
            try {
                const result = await this.write(this.revision, content);
                this.revision = result.revision; this.saved = serialized;
            } catch (e) {
                this.status = (e as { status?: number }).status === 409 ? 'conflict' : 'error';
                this.error = e instanceof Error ? e.message : '保存失败';
                this.cancelTimers(); this.notify(); return false;
            }
        }
        this.cancelTimers(); this.status = 'saved'; this.notify(); return !this.disposed;
    }
    resume() { this.disposed = false; }
    dispose() { this.disposed = true; this.cancelTimers(); }
}
