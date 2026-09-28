import { useEffect, useRef, useState } from 'react';
import { Player } from '@remotion/player';
import { ImageDown, Sparkles } from 'lucide-react';
import { Cover } from '../video/Cover';
import { Button } from './ui/button';
import { api } from '../lib/media';
import type { CoverConfig, Project } from '../lib/project';
import {
    applyCoverCandidates, coverAudiences, coverConflicts, coverCopySource, coverExportReady, coverQuestionTitle,
    defaultCover, defaultCoverPhoto, isQuestionCover, moveCoverPhoto, selectedCoverWords,
} from '../lib/cover-layout';
import type { CoverCopy } from '../../../server/src/core/image-analysis/cover-copy';

export function CoverEditor({ project, update, disabled, onExport }: {
    project: Project; update: (project: Project) => void; disabled: boolean; onExport: () => void;
}) {
    const [generating, setGenerating] = useState(false);
    const [notice, setNotice] = useState('');
    const latest = useRef(project); latest.current = project;
    const source = coverCopySource(project);
    const sourceVersion = useRef({ source, version: 0 });
    if (sourceVersion.current.source !== source) sourceVersion.current = { source, version: sourceVersion.current.version + 1 };
    const request = useRef(0);
    useEffect(() => () => { request.current++; }, []);
    const drag = useRef<{ x: number; y: number; project: Project } | null>(null);
    const cover = project.cover ?? defaultCover;
    const question = isQuestionCover(project);
    const audience = cover.audience ?? 'adult';
    const photo = cover.photo ?? defaultCoverPhoto;
    const selected = selectedCoverWords(project);
    const conflicts = coverConflicts(project);
    const stale = !!cover.candidates && cover.candidateSource !== source;
    function patch(patch: Partial<CoverConfig>) {
        const current = latest.current;
        update({ ...current, cover: { ...(current.cover ?? defaultCover), ...patch } });
    }
    async function generate() {
        const currentRequest = ++request.current;
        const version = sourceVersion.current.version;
        const snapshot = latest.current;
        const requestedSource = coverCopySource(snapshot);
        setGenerating(true); setNotice('');
        try {
            const candidates = await api<CoverCopy>('cover-copy', snapshot);
            if (request.current !== currentRequest) return;
            if (version !== sourceVersion.current.version || requestedSource !== coverCopySource(latest.current)) {
                setNotice('照片或内容已改变，本次标题建议未应用，请重新生成。'); return;
            }
            update(applyCoverCandidates(latest.current, requestedSource, candidates));
            setNotice('三类标题已生成。点击候选才会替换当前标题。');
        } catch (error) {
            if (request.current === currentRequest) setNotice(error instanceof Error ? error.message : '标题生成失败，请重试');
        } finally { if (request.current === currentRequest) setGenerating(false); }
    }
    const preview = <Player component={Cover} compositionWidth={1080} compositionHeight={1440} durationInFrames={1} fps={30} controls={false} clickToPlay={false} style={{ width: '100%', pointerEvents: 'none' }} inputProps={{ project }} />;
    return <div className="cover-editor">
        <div className={`drawer-preview ${question ? 'cover-crop-preview' : ''}`} aria-label="封面预览，可使用下方滑块调整取景"
            style={{ touchAction: question && !disabled ? 'none' : 'auto' }}
            onPointerDown={event => {
                if (!question || disabled || !project.image) return;
                event.currentTarget.setPointerCapture(event.pointerId);
                drag.current = { x: event.clientX, y: event.clientY, project: latest.current };
            }}
            onPointerMove={event => {
                if (!drag.current) return;
                const ratio = 1080 / event.currentTarget.getBoundingClientRect().width;
                patch({ photo: moveCoverPhoto(drag.current.project, (event.clientX - drag.current.x) * ratio, (event.clientY - drag.current.y) * ratio) });
            }}
            onPointerUp={() => { drag.current = null; }} onPointerCancel={() => { drag.current = null; }} onLostPointerCapture={() => { drag.current = null; }}>
            {preview}
        </div>
        <p className="hint">3:4 · 1080×1440{question ? ' · 拖动照片调整取景，文字保持固定' : ' · 旧版学习卡'}</p>
        <fieldset disabled={disabled} className="cover-controls">
            <label className="field-label" htmlFor="coverTemplate">封面样式</label>
            <select id="coverTemplate" className="input" value={cover.template} onChange={event => patch({ template: event.target.value as CoverConfig['template'] })}>
                <option value="scene-question">场景问题</option><option value="learning-card">经典学习卡</option>
            </select>
            {question ? <>
                <div className="cover-section-label">01 / 标题</div>
                <div className="cover-audiences" role="group" aria-label="标题受众">{coverAudiences.map(item => <button type="button" key={item.id} aria-pressed={audience === item.id} onClick={() => patch({ audience: item.id })}>{item.label}</button>)}</div>
                <label className="field-label" htmlFor="questionTitle">封面问题 <span className="hint">最多两行 · 40 字以内</span></label>
                <textarea id="questionTitle" className="input cover-title-input" rows={2} maxLength={40} value={cover.audienceTitles?.[audience] ?? coverQuestionTitle(project)} onChange={event => patch({ audienceTitles: { ...cover.audienceTitles, [audience]: event.target.value } })} />
                <Button variant="outline" className="w-full" disabled={generating || !project.image || !project.caption.trim() || !project.words.length} onClick={generate}><Sparkles />{generating ? '正在生成三类标题…' : '生成标题建议'}</Button>
                <p className="hint">生成三个受众版本，每类三个候选；保留你已编辑的标题。</p>
                {notice && <p className="cover-notice" role="status">{notice}</p>}
                {stale && <p className="cover-notice">内容已变化，请重新生成标题建议。</p>}
                <div className="cover-candidates">{cover.candidates?.[audience].map((title, index) => <button type="button" key={`${index}-${title}`} disabled={stale} onClick={() => patch({ audienceTitles: { ...cover.audienceTitles, [audience]: title } })}><span>0{index + 1}</span>{title}</button>)}</div>
                <label className="field-label" htmlFor="titlePosition">文字位置</label>
                <select id="titlePosition" className="input" value={cover.titlePosition ?? 'top'} onChange={event => patch({ titlePosition: event.target.value as 'top' | 'bottom' })}><option value="top">顶部</option><option value="bottom">底部</option></select>
                <div className="cover-section-label">02 / 精选词 <span>{selected.length} / 3</span></div>
                <p className="hint">最多三个，可全部隐藏。只影响封面。</p>
                <div className="cover-highlight-list">{project.words.map(word => {
                    const checked = selected.some(item => item.id === word.id);
                    return <label key={word.id}><input type="checkbox" checked={checked} disabled={!checked && selected.length >= 3} onChange={() => patch({ selectedWordIds: checked ? selected.filter(item => item.id !== word.id).map(item => item.id) : [...selected.map(item => item.id), word.id] })} /><span>{word.english}</span></label>;
                })}</div>
                <Button variant="ghost" size="sm" onClick={() => patch({ selectedWordIds: [] })}>隐藏全部词</Button>
                <Button variant="ghost" size="sm" onClick={() => patch({ selectedWordIds: undefined })}>恢复默认精选</Button>
                <div className="cover-section-label">03 / 照片取景</div>
                {([{ key: 'zoom', label: '缩放', min: 1, max: 2 }, { key: 'x', label: '水平位置', min: 0, max: 1 }, { key: 'y', label: '垂直位置', min: 0, max: 1 }] as const).map(item => <label className="range-field" key={item.key}><span>{item.label}<strong>{Math.round(photo[item.key] * 100)}%</strong></span><input aria-label={item.label} type="range" min={item.min} max={item.max} step=".01" value={photo[item.key]} onChange={event => patch({ photo: { ...photo, [item.key]: Number(event.target.value) } })} /></label>)}
                <Button variant="ghost" size="sm" onClick={() => patch({ photo: { ...defaultCoverPhoto } })}>重置取景</Button>
                <details className="cover-thumbnail" open><summary>信息流缩略图 · 180×240</summary><div style={{ width: 180, height: 240, margin: '16px auto' }}>{preview}</div></details>
            </> : <>
                <label className="field-label" htmlFor="coverTitle">封面场景标题</label>
                <input id="coverTitle" className="input" maxLength={40} value={cover.title ?? ''} placeholder={project.sceneTheme || project.title} onChange={event => patch({ title: event.target.value || undefined })} />
                <label className="range-field"><span>全部胶囊<strong>{Math.round(cover.scale * 100)}%</strong></span><input aria-label="全部胶囊大小" type="range" min=".72" max="1.15" step=".01" value={cover.scale} onChange={event => patch({ scale: Number(event.target.value) })} /></label>
                <div className="cover-highlight-picker"><h3>高亮单词</h3><div className="cover-highlight-list">{project.words.map(word => <label key={word.id}><input type="checkbox" checked={cover.words[word.id]?.highlighted ?? false} onChange={event => patch({ words: { ...cover.words, [word.id]: { ...(cover.words[word.id] ?? { scale: 1 }), highlighted: event.target.checked } } })} /><span>{word.english}</span></label>)}</div></div>
                {project.words.filter(word => (word.kind ?? 'object') === 'object').map(word => <label className="range-field" key={word.id}><span>{word.english}</span><input aria-label={`${word.english} 胶囊大小`} type="range" min=".85" max="1.2" step=".01" value={cover.words[word.id]?.scale ?? 1} onChange={event => patch({ words: { ...cover.words, [word.id]: { ...cover.words[word.id], scale: Number(event.target.value) } } })} /></label>)}
            </>}
            {conflicts.map(issue => <p key={issue} className="cover-error" role="alert">{issue}</p>)}
            <Button className="w-full" disabled={!coverExportReady(project)} onClick={onExport}><ImageDown />导出封面 PNG</Button>
        </fieldset>
    </div>;
}
