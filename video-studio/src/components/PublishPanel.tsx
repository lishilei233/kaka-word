import { useState } from 'react';
import type { Project } from '../lib/project';
import { publishingIssues, publishingPost, publishingText } from '../lib/learning-post';
import { PublishingSceneField } from './PublishingSceneField';
import { Button } from './ui/button';

export function PublishPanel({ project, update, disabled = false }: { project: Project; update: (project: Project) => void; disabled?: boolean }) {
    const [notice, setNotice] = useState<{ text: string; source: string }>();
    const source = publishingText(project, 'all');
    const post = publishingPost(project);
    const issues = publishingIssues(project);
    async function copy(part: 'title' | 'body' | 'all') {
        if (issues.length || disabled) return;
        try {
            await navigator.clipboard.writeText(publishingText(project, part));
            setNotice({ text: '已复制', source });
        } catch { setNotice({ text: '复制失败，请重试或选中预览文字手动复制。', source }); }
    }
    return <section className="publish-board">
        <fieldset className="cover-controls" disabled={disabled}><PublishingSceneField project={project} update={update} id="publishingScene" /></fieldset>
        <article className="publish-card">
            <header><div><small>PHOTO ENGLISH</small><h2>固定发布文案</h2></div></header>
            <p className="hint">适用于小红书、抖音、视频号。修改场景名、词表或照片描述后自动同步。</p>
            {issues.length > 0 ? <div role="status" className="cover-error">{issues.map(issue => <p key={issue}>{issue}</p>)}</div> : null}
            <label>标题<input value={post.title} readOnly /></label>
            <label>正文与话题<textarea value={publishingText(project, 'body')} readOnly rows={16} /></label>
            <div className="publish-copy-actions">
                <Button variant="outline" size="sm" disabled={disabled || !!issues.length} onClick={() => void copy('title')}>复制标题</Button>
                <Button variant="outline" size="sm" disabled={disabled || !!issues.length} onClick={() => void copy('body')}>复制正文与话题</Button>
                <Button size="sm" disabled={disabled || !!issues.length} onClick={() => void copy('all')}>复制全文</Button>
            </div>
            {notice?.source === source && <p role="status" className="hint">{notice.text}</p>}
        </article>
    </section>;
}
