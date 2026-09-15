import type { Project, SocialCopy } from '../lib/project';
import { Button } from './ui/button';

const platforms = [
    ['xiaohongshu', '小红书', 'RED NOTE'],
    ['douyin', '抖音', 'DOUYIN'],
    ['channels', '视频号', 'WECHAT CHANNELS'],
] as const;

export function PublishPanel({ project, update }: { project: Project; update: (project: Project) => void }) {
    function edit(platform: keyof SocialCopy, patch: Partial<SocialCopy[keyof SocialCopy]>) {
        if (!project.socialCopy) return;
        update({ ...project, socialCopy: { ...project.socialCopy, [platform]: { ...project.socialCopy[platform], ...patch } } });
    }
    async function copy(platform: keyof SocialCopy) {
        const post = project.socialCopy?.[platform];
        if (!post) return;
        await navigator.clipboard.writeText([post.title, post.body, post.hashtags.map(tag => `#${tag}`).join(' ')].filter(Boolean).join('\n\n'));
    }
    if (!project.socialCopy) return <section className="publish-empty"><span>✦</span><h2>让这一张照片，去到更多地方。</h2><p>AI 会根据最终照片描述、词表和封面高亮词，为三个平台分别写文案。</p></section>;
    return <section className="publish-board">
        {platforms.map(([id, label, eyebrow], index) => {
            const post = project.socialCopy![id];
            return <article className={`publish-card publish-${id}`} key={id}>
                <header><span>{String(index + 1).padStart(2, '0')}</span><div><small>{eyebrow}</small><h2>{label}</h2></div><Button variant="ghost" size="sm" onClick={() => void copy(id)}>复制全文</Button></header>
                <label>标题<input value={post.title} maxLength={80} onChange={event => edit(id, { title: event.target.value })} /></label>
                <label>正文<textarea value={post.body} maxLength={1000} onChange={event => edit(id, { body: event.target.value })} /></label>
                <label>话题标签<input value={post.hashtags.join(' ')} onChange={event => edit(id, { hashtags: event.target.value.split(/[\s#，,]+/).filter(Boolean).slice(0, 12) })} /></label>
                <div className="publish-tags">{post.hashtags.map(tag => <span key={tag}>#{tag}</span>)}</div>
            </article>;
        })}
    </section>;
}
