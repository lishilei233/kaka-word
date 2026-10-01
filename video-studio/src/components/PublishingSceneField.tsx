import type { Project } from '../lib/project';
import { fixedCoverTitle, PUBLISHING_SCENE_LIMIT, publishingSceneIssues } from '../lib/learning-post';

export function PublishingSceneField({ project, update, id }: { project: Project; update: (project: Project) => void; id: string }) {
    return <div className="publishing-scene-field">
        <label className="field-label" htmlFor={id}>场景名</label>
        <input id={id} className="input" maxLength={PUBLISHING_SCENE_LIMIT} value={project.publishingScene ?? project.sceneTheme ?? ''}
            placeholder="例如：书架一角" onChange={event => update({ ...project, publishingScene: event.target.value })} />
        <p className="hint">最多 29 字，封面与三个平台文案同步使用。</p>
        <p className="hint">封面标题：{fixedCoverTitle(project) || '请先填写场景名'}</p>
        {publishingSceneIssues(project).map(issue => <p key={issue} role="status" className="cover-error">{issue}</p>)}
    </div>;
}
