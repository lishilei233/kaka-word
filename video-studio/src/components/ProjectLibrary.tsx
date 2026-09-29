import { useEffect, useState } from 'react';
import { Link, useNavigate } from '@tanstack/react-router';
import { Camera, Copy, Film, Plus, Trash2, Pencil } from 'lucide-react';
import { api } from '../lib/media';
import type { ProjectRecord, ProjectSummary } from '../lib/project-record';
import { Button } from './ui/button';

export function ProjectLibrary() {
    const [items, setItems] = useState<ProjectSummary[]>([]);
    const [loading, setLoading] = useState(true);
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState('');
    const navigate = useNavigate();
    async function load() {
        setLoading(true); setError('');
        try { setItems(await api<ProjectSummary[]>('projects')); }
        catch (e) { setError((e as Error).message); }
        finally { setLoading(false); }
    }
    useEffect(() => { void load(); }, []);
    async function act(work: () => Promise<void>) {
        setBusy(true); setError('');
        try { await work(); } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
    }
    async function open(record: ProjectRecord) { await navigate({ to: '/projects/$projectId', params: { projectId: record.id } }); }
    return <main className="studio-shell library">
        <header className="studio-header"><div className="brand"><span className="brand-stamp"><Camera /></span><div><strong>咔咔单词<span className="brand-dot">.</span></strong><span className="eyebrow">VIDEO STUDIO / 视频工作室</span></div></div><span className="local-badge"><span />保存在本机</span></header>
        <div className="library-intro"><div><span className="eyebrow">YOUR EVERYDAY FILMS</span><h1>我的作品<span className="brand-dot">.</span></h1><p>收藏生活的画面，把每一张照片做成一堂小课。</p></div><Button disabled={busy || loading || !!error} onClick={() => act(async () => open(await api<ProjectRecord>('projects', {})))}><Plus />新建视频</Button></div>
        {error && <div role="alert" className="project-error">{error}<Button variant="outline" disabled={busy} onClick={load}>重新加载</Button></div>}
        {loading ? <p role="status">正在读取作品…</p> : !items.length && !error ? <section className="library-empty"><Film size={40} /><h2>第一部小课，从这里开始</h2><p>点击“新建视频”，导入照片或视频。编辑内容会自动保存。</p></section> : <div className="project-grid">{items.map((item, index) => <article className="project-card" key={item.id}>
            <Link to="/projects/$projectId" params={{ projectId: item.id }} className="project-open" aria-label={`打开作品：${item.title || '未命名视频'}`}><div className="project-thumb">{item.image ? <img src={item.image} alt="" loading="lazy" /> : <Film size={36} />}<span className="project-number">{String(index + 1).padStart(2, '0')}</span></div><h2>{item.title || '未命名视频'}</h2><p>最后编辑 <time dateTime={item.updatedAt}>{new Date(item.updatedAt).toLocaleString('zh-CN')}</time></p></Link>
            <div className="project-card-actions"><Button variant="ghost" size="sm" disabled={busy} onClick={() => {
                const title = window.prompt('作品名称（最多 80 字）', item.title);
                if (title === null || !title.trim()) return;
                void act(async () => {
                    if (title.trim().length > 80) throw new Error('作品名称最多 80 字');
                    const record = await api<ProjectRecord>(`projects/${item.id}`);
                    await api(`projects/${item.id}`, { revision: record.revision, content: { project: { ...record.project, title: title.trim() }, editor: record.editor } });
                    await load();
                });
            }}><Pencil size={14} />命名</Button><Button variant="ghost" size="sm" disabled={busy} onClick={() => act(async () => open(await api<ProjectRecord>(`projects/${item.id}/copy`, {})))}><Copy size={14} />复制</Button><Button variant="ghost" size="sm" disabled={busy} aria-label={`删除作品：${item.title}`} onClick={() => {
                if (!window.confirm(`删除“${item.title || '未命名视频'}”？此操作无法撤销，其他作品不会受影响。`)) return;
                void act(async () => { await api(`projects/${item.id}/delete`, { revision: item.revision }); await load(); });
            }}><Trash2 size={14} />删除</Button></div>
        </article>)}</div>}
        <footer className="studio-footer"><span>ONE FRAME, ONE LITTLE LESSON.</span><span>作品、素材与配音均保存在本机 .data 目录</span></footer>
    </main>;
}
