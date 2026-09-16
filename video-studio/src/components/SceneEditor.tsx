import { useState } from 'react';
import type { Project, Word } from '../lib/project';
import { Button } from './ui/button';

export function SceneEditor({ project: p, update, onEditArrow }: { project: Project; update: (p: Project) => void; onEditArrow?: () => void }) {
    const interaction = p.interaction ?? { enabled: false, english: '', chinese: '' };
    return <section className="scene-editor">
        <label className="field-label" htmlFor="analysisMode">选词方式</label>
        <select id="analysisMode" className="input" value={p.analysisMode ?? 'objects'} onChange={e => update({ ...p, analysisMode: e.target.value as Project['analysisMode'] })}>
            <option value="scene">场景学词 · 物体、动作、状态</option><option value="objects">物体识别 · 照片标签</option>
        </select>
        {p.analysisMode === 'scene' && <><label className="field-label" htmlFor="sceneContext">这张照片发生了什么？（可选）</label><textarea id="sceneContext" className="input caption-input" maxLength={500} placeholder="例如：鸡蛋刚掉到地上。没有背景也可以，只描述看得见的内容。" value={p.sceneContext ?? ''} onChange={e => update({ ...p, sceneContext: e.target.value })} /><p className="hint">修改后点击 AI 识别生效。动作、状态词将展示在照片底部。</p></>}
        {p.sceneTheme && <p className="scene-theme">本期场景 · {p.sceneTheme}</p>}
        <details className="interaction-editor"><summary>结尾互动句 {interaction.enabled ? '· 已开启' : '· 未开启'}</summary>
            <label className="safe-toggle"><input type="checkbox" checked={interaction.enabled} onChange={e => update({ ...p, interaction: { ...interaction, enabled: e.target.checked } })} />在场景句之后展示并朗读</label>
            <label className="field-label" htmlFor="interactionEnglish">互动句 · English</label><textarea id="interactionEnglish" className="input caption-input" value={interaction.english} maxLength={220} onChange={e => update({ ...p, interaction: { ...interaction, english: e.target.value, audio: undefined, audioSeconds: undefined } })} />
            <label className="field-label" htmlFor="interactionChinese">互动句 · 中文</label><textarea id="interactionChinese" className="input caption-input" value={interaction.chinese} maxLength={220} onChange={e => update({ ...p, interaction: { ...interaction, chinese: e.target.value } })} />
            <label className="safe-toggle"><input type="checkbox" checked={interaction.arrowEnabled ?? false} disabled={!interaction.enabled} onChange={e => update({ ...p, interaction: { ...interaction, arrowEnabled: e.target.checked, arrowTarget: interaction.arrowTarget ?? { x: .5, y: .45 } } })} />朗读互动句时显示指向箭头</label>
            {interaction.enabled && interaction.arrowEnabled && <><Button type="button" variant="secondary" size="sm" onClick={onEditArrow}>去预览定位箭头</Button><p className="hint">进入互动提问画面后，拖动箭头尖端指向照片中的物体。</p></>}
            <p className="hint">视频默认关闭互动句；发布文案可以保留这个问题。</p>
        </details>
    </section>;
}

export function WordKindEditor({ word, image, edit }: { word: Word; image?: string; edit: (patch: Partial<Word>) => void }) {
    const [point, setPoint] = useState<{ id: string; x: number; y: number }>();
    const selected = point?.id === word.id ? point : undefined;
    return <>
        <label className="field-label" htmlFor="wordKind">词汇类型</label><select id="wordKind" className="input" value={word.kind ?? 'object'} onChange={e => {
            const kind = e.target.value as Word['kind'];
            edit({ kind, box: undefined, needsLocation: kind === 'object', labelCenterOverride: undefined, targetCenterOverride: undefined });
        }}><option value="object">物体 · 照片内标注</option><option value="action">动作 · 下方词卡</option><option value="state">状态 · 下方词卡</option></select>
        {(word.kind ?? 'object') === 'object' && (!word.box || word.needsLocation) && <div className="location-picker"><p>点击照片中对应物体，再确认定位。确认前不显示引导线。</p>
            <button type="button" aria-label="点击照片选择物体位置" style={{ display: 'block', width: '100%', position: 'relative' }} onClick={e => {
                const bounds = e.currentTarget.getBoundingClientRect();
                setPoint({ id: word.id, x: Math.max(.05, Math.min(.95, (e.clientX - bounds.left) / bounds.width)), y: Math.max(.05, Math.min(.95, (e.clientY - bounds.top) / bounds.height)) });
            }}>{image && <img src={image} alt="选择物体位置" style={{ width: '100%', display: 'block' }} />}{selected && <span style={{ position: 'absolute', left: `${(selected.x-.05)*100}%`, top: `${(selected.y-.05)*100}%`, width: '10%', height: '10%', border: '2px solid #e36c5f', background: '#f4c95d55' }} />}</button>
            <Button variant="secondary" size="sm" disabled={!selected} onClick={() => selected && edit({ box: { x: selected.x-.05, y: selected.y-.05, width: .1, height: .1 }, needsLocation: false })}>确认定位</Button>
        </div>}
    </>;
}
