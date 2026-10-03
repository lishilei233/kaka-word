import type { Word } from '../lib/project';
import { constrainRecognitionBox, recognitionBox } from '../lib/recognition';
import { Button } from './ui/button';
export function RecognitionEditor({ word, words, select, editing, edit, toggle, preview }: { word?: Word; words: Word[]; select: (word: Word) => void; editing: boolean; edit: (patch: Partial<Word>) => void; toggle: () => void; preview: () => void }) {
    const objects = words.filter(item => (item.kind ?? 'object') === 'object');
    const object = word && (word.kind ?? 'object') === 'object' ? word : undefined;
    const box = object && recognitionBox(object);
    return <section className="recognition-settings"><h3>识别框</h3>
        <label className="field-label" htmlFor="recognitionWord">选择物体词</label>
        <select id="recognitionWord" className="input" value={object?.id ?? ''} disabled={!objects.length} onChange={event => { const next = objects.find(item => item.id === event.target.value); if (next) select(next); }}>
            <option value="" disabled>{objects.length ? '选择要调整的物体' : '识别照片后可调整'}</option>
            {objects.map(item => <option key={item.id} value={item.id}>{item.english} · {item.chinese}</option>)}
        </select>
        {!object ? <p className="hint">选择上方或左侧的物体词，可调整四角识别框的位置和大小。</p> : !box ? <p className="hint">请先在下方定位物体</p> : <>
        <p className="hint">高亮时四角向内收拢对焦，并保留到下个单词。暂停选词可查看范围，点击调整可拖动四角。</p>
        <div className="publish-copy-actions"><Button size="sm" variant="outline" onClick={toggle}>{editing ? '完成调整' : '调整识别框'}</Button><Button size="sm" variant="outline" onClick={preview}>预览动画</Button></div>
        <div className="position-grid">{(['x', 'y', 'width', 'height'] as const).map((key, index) => <label key={key}><span>{['横向', '纵向', '宽度', '高度'][index]} <small>{(box[key] * 100).toFixed(1)}%</small></span><input aria-label={`识别框${['横向', '纵向', '宽度', '高度'][index]}`} type="range" min={index < 2 ? 0 : 2} max={100} step=".1" value={box[key] * 100} onChange={event => edit({ recognitionBoxOverride: constrainRecognitionBox({ ...box, [key]: Number(event.target.value) / 100 }) })} /></label>)}</div>
        <Button variant="ghost" size="sm" disabled={!object.recognitionBoxOverride} onClick={() => edit({ recognitionBoxOverride: undefined })}>恢复自动范围</Button>
    </>}</section>;
}
