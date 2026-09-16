import { Cover } from '../video/Cover';
import { PublishPanel } from './PublishPanel';
import { coverLayout, defaultCover } from '../lib/cover-layout';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Player, type PlayerRef } from '@remotion/player';
import { ArrowDown, ArrowUp, Camera, Check, ChevronRight, Download, Film as FilmIcon, ImageDown, ImagePlus, LoaderCircle, Play, Plus, Save, Sparkles, Trash2, Volume2 } from 'lucide-react';
import { Button } from './ui/button';
import { Film } from '../video/Film';
import { api, snapshot, upload, uploadApplePhoto } from '../lib/media';
import { changeEnglish, emptyProject, exportBlockers, exportReady, FPS, projectSchema, selectCaptionVariant, sortByPhotoPosition, timeline, voiceOptions, type Project, type Word } from '../lib/project';
import { annotationLayout, sortByAnnotationPosition } from '../lib/annotation-layout';
import { filmLayout } from '../lib/film-layout';

type CaptionStyle = 'serious' | 'funny' | 'literary';
type CaptionVariant = { caption: string; captionChinese: string };
type Analysis = { caption: string; captionChinese: string; captionVariants?: Record<CaptionStyle, CaptionVariant>; objects: { id: string; english: string; chinese: string; ipa: string; box: { x: number; y: number; width: number; height: number } }[] };
export function Studio() {
    const [project, setProject] = useState<Project>(emptyProject);
    const [mode, setMode] = useState<'video' | 'cover' | 'publish'>('video');
    const [ready, setReady] = useState(false);
    const [busy, setBusy] = useState(''); const [message, setMessage] = useState(''); const [error, setError] = useState('');
    const [showSafeAreas, setShowSafeAreas] = useState(true);
    const [selected, setSelected] = useState(''); const [count, setCount] = useState(8);
    const [source, setSource] = useState(''); const [sourceDuration, setSourceDuration] = useState(0);
    const [job, setJob] = useState<string>(); const [progress, setProgress] = useState(0); const [download, setDownload] = useState('');
    const input = useRef<HTMLInputElement>(null); const video = useRef<HTMLVideoElement>(null); const player = useRef<PlayerRef>(null);
    const revision = useRef(0); const initialLoad = useRef(false); const pendingLivePhotoVideo = useRef('');
    const coverConflicts = useMemo(() => mode === 'cover' ? coverLayout(project).conflicts : [], [mode, project.cover, project.words, project.imageWidth, project.imageHeight]);
    const t = timeline(project); const word = project.words.find(w => w.id === selected); const exportIssues = exportBlockers(project);
    const imageFrame = filmLayout(project).photoImage;
    const selectedPlacement = annotationLayout(project.words, imageFrame, selected).placements.find(placement => placement.id === selected);
    const selectedCenter = selectedPlacement ? {
        x: (selectedPlacement.labelCenter.x - imageFrame.x) / imageFrame.width,
        y: (selectedPlacement.labelCenter.y - imageFrame.y) / imageFrame.height,
    } : { x: .5, y: .5 };
    const selectedTarget = word?.targetCenterOverride ?? (word ? {
        x: word.box.x + word.box.width / 2,
        y: word.box.y + word.box.height / 2,
    } : { x: .5, y: .5 });
    useEffect(() => {
        if (initialLoad.current) return; initialLoad.current = true;
        api<Project | null>('project').then(p => {
            if (p) { const saved = projectSchema.parse(p); setProject({ ...saved, safeTop: 120, safeBottom: 240, safeRight: 0 }); if (saved.video) setSource(saved.video); }
        }).catch(e => setError(e.message)).finally(() => setReady(true));
    }, []);
    useEffect(() => {
        if (!job) return;
        let cancelled = false;
        const timer = setInterval(() => {
            api<{ status: string; progress: number; error?: string; file?: string }>(`jobs/${job}`).then(result => {
                if (cancelled) return;
                setProgress(result.progress);
                if (result.status === 'complete') { setDownload(result.file!); setJob(undefined); setMessage('视频已导出，可以下载了'); }
                if (result.status === 'failed') { setError(result.error || '导出失败'); setJob(undefined); }
            }).catch(e => { if (!cancelled) { setError(e.message); setJob(undefined); } });
        }, 1500);
        return () => { cancelled = true; clearInterval(timer); };
    }, [job]);
    function update(p: Project) { if (p.cover) p = { ...p, cover: { ...p.cover, words: Object.fromEntries(Object.entries(p.cover.words).filter(([id]) => p.words.some(w => w.id === id))) } }; revision.current++; setProject(p); setDownload(''); }
    function editWord(patch: Partial<Word>) { update({ ...project, socialCopy: undefined, words: project.words.map(w => w.id === selected ? { ...w, ...patch } : w) }); }
    function moveAnnotation(id: string, kind: 'label' | 'target', point: { x: number; y: number }) {
        setSelected(id);
        let words = project.words.map(w => w.id === id ? {
            ...w, [kind === 'label' ? 'labelCenterOverride' : 'targetCenterOverride']: point,
        } : w);
        if (kind === 'label') words = sortByAnnotationPosition(words, imageFrame, id);
        update({ ...project, words });
    }
    async function run(label: string, work: () => Promise<void>) {
        setBusy(label); setError(''); setMessage('');
        try { await work(); } catch (e) { setError(e instanceof Error ? e.message : '操作失败'); } finally { setBusy(''); }
    }
    async function importFile(file?: File) {
        if (!file) return;
        if (file.size > 100 * 1024 * 1024) { setError('请选择 100 MB 以内的图片或视频'); return; }
        await run('导入素材', async () => {
            if (file.type.startsWith('video/')) {
                pendingLivePhotoVideo.current = '';
                const ext = file.name.split('.').pop()?.toLowerCase();
                if (!ext || !['mp4', 'mov', 'webm'].includes(ext)) throw new Error('请选择 MP4、MOV 或 WebM 视频');
                const url = await upload(file, ext); setSource(url);
                update({ ...project, image: undefined, video: undefined, words: [], caption: '', captionChinese: '', captionVariants: undefined, selectedCaptionStyle: 'serious', captionAudio: undefined, captionAudioSeconds: undefined }); setSelected('');
                setMessage('拖动视频进度，选好画面后点击「使用这一帧」');
            } else if (file.type.startsWith('image/')) {
                pendingLivePhotoVideo.current = '';
                const imageExt = file.name.split('.').pop()?.toLowerCase();
                if (imageExt === 'heic' || imageExt === 'heif') {
                    const converted = await uploadApplePhoto(file, imageExt);
                    setSource('');
                    update({ ...project, image: converted.url, imageWidth: converted.imageWidth, imageHeight: converted.imageHeight, video: undefined, words: [], caption: '', captionChinese: '', captionVariants: undefined, selectedCaptionStyle: 'serious', captionAudio: undefined, captionAudioSeconds: undefined }); setSelected('');
                    setMessage('HEIC 已转换为照片，可以开始识别；如需动态效果，请同时选择配套 MOV');
                } else {
                    const objectUrl = URL.createObjectURL(file);
                    try {
                        const image = new Image(); image.src = objectUrl; await image.decode();
                        const frame = await snapshot(image); setSource('');
                        update({ ...project, ...frame, video: undefined, words: [], caption: '', captionChinese: '', captionVariants: undefined, selectedCaptionStyle: 'serious', captionAudio: undefined, captionAudioSeconds: undefined }); setSelected('');
                        setMessage('照片已准备好，可以开始识别');
                    } finally { URL.revokeObjectURL(objectUrl); }
                }
            } else throw new Error('请选择图片或视频');
        });
    }
    async function importFiles(files: File[]) {
        if (!files.length) return;
        const videoFile = files.find(file => file.type.startsWith('video/') || /\.(mov|mp4|webm)$/i.test(file.name));
        const imageFile = files.find(file => file.type.startsWith('image/') || /\.(heic|heif|jpe?g|png)$/i.test(file.name));
        if (!videoFile || !imageFile) { await importFile(files[0]); return; }
        if (videoFile.size > 100 * 1024 * 1024 || imageFile.size > 100 * 1024 * 1024) { setError('请选择单个文件不超过 100 MB 的素材'); return; }
        await run('导入 Apple 动态照片', async () => {
            const videoExt = videoFile.name.split('.').pop()?.toLowerCase();
            if (!videoExt || !['mov', 'mp4', 'webm'].includes(videoExt)) throw new Error('动态照片视频格式不受支持');
            const stillExt = imageFile.name.split('.').pop()?.toLowerCase();
            let frame: { image: string; imageWidth: number; imageHeight: number };
            if (stillExt === 'heic' || stillExt === 'heif') {
                const converted = await uploadApplePhoto(imageFile, stillExt);
                frame = { image: converted.url, imageWidth: converted.imageWidth, imageHeight: converted.imageHeight };
            } else {
                const objectUrl = URL.createObjectURL(imageFile);
                try { const image = new Image(); image.src = objectUrl; await image.decode(); frame = await snapshot(image); }
                finally { URL.revokeObjectURL(objectUrl); }
            }
            const videoUrl = await upload(videoFile, videoExt);
            pendingLivePhotoVideo.current = videoUrl;
            setSource(videoUrl);
            update({ ...project, ...frame, video: videoUrl, captureSeconds: 0, introSeconds: 2, words: [], caption: '', captionChinese: '', captionVariants: undefined, selectedCaptionStyle: 'serious', captionAudio: undefined, captionAudioSeconds: undefined });
            setSelected(''); setMessage('Apple 动态照片已导入：取景框将播放 MOV 的最后 2 秒');
        });
    }
    async function capture() {
        if (!video.current) return;
        const element = video.current; element.pause();
        await run('截取照片', async () => {
            const frame = await snapshot(element);
            update({ ...project, ...frame, video: source, captureSeconds: element.currentTime, words: [], caption: '', captionChinese: '', captionVariants: undefined, selectedCaptionStyle: 'serious', captionAudio: undefined, captionAudioSeconds: undefined });
            setSelected(''); setMessage('已选定拍摄帧，识别和成片将使用这张照片');
        });
    }
    async function analyze() {
        await run('识别物体', async () => {
            const version = revision.current;
            const result = await api<Analysis>('analyze', { image: project.image, maxObjects: count });
            if (version !== revision.current) return;
            const orderedObjects = sortByPhotoPosition(result.objects);
            const words: Word[] = orderedObjects.map((w, index) => ({
                id: `${w.id}-${index}`, english: w.english, chinese: w.chinese, ipa: w.ipa,
                box: w.box,
            }));
            const fallback = { caption: result.caption, captionChinese: result.captionChinese };
            const captionVariants = result.captionVariants ?? { serious: fallback, funny: fallback, literary: fallback };
            update({ ...project, words, captionVariants, selectedCaptionStyle: 'serious', ...captionVariants.serious, captionAudio: undefined, captionAudioSeconds: undefined, socialCopy: undefined }); setSelected(words[0]?.id || '');
            player.current?.seekTo(t.intro + t.reveal);
            setMessage(words.length ? `找到 ${words.length} 个单词，请校对名称和标签位置` : '没有找到可靠的物体，试试另一张照片或手动添加');
        });
    }
    async function speech() {
        await run('生成配音', async () => {
            const version = revision.current;
            const result = await api<{ words: Pick<Word, 'id' | 'english' | 'audio' | 'audioSeconds'>[]; captionAudio: string; captionAudioSeconds: number }>('speech', { words: project.words.map(({ id, english }) => ({ id, english })), caption: project.caption, voiceId: project.voiceId, speechSpeed: project.speechSpeed });
            if (revision.current !== version) return;
            update({ ...project, captionAudio: result.captionAudio, captionAudioSeconds: result.captionAudioSeconds, words: project.words.map(w => ({ ...w, ...result.words.find(a => a.id === w.id && a.english === w.english) })) });
            setMessage('配音已就绪，点击预览播放即可跟读');
        });
    }
    async function generatePublishingCopy() {
        await run('生成发布文案', async () => {
            const socialCopy = await api<Project['socialCopy']>('social-copy', project);
            update({ ...project, socialCopy });
            setMessage('三个平台的发布文案已生成，可以继续校对或复制');
        });
    }
    async function exportCurrentFrame() {
        await run('导出当前帧', async () => {
            const frame = player.current?.getCurrentFrame() ?? 0;
            const result = await api<{ file: string; frame: number }>('render-still', { project, frame });
            const link = document.createElement('a'); link.href = result.file; link.download = `kakaword-frame-${result.frame}.png`; link.click();
            setMessage(`第 ${result.frame} 帧已导出为 PNG`);
        });
    }
    function selectWord(w: Word) {
        setSelected(w.id); player.current?.pause();
        player.current?.seekTo(t.words.find(item => item.word.id === w.id)!.from);
    }
    function reorder(index: number, direction: number) {
        const words = [...project.words]; [words[index], words[index + direction]] = [words[index + direction], words[index]];
        update({ ...project, words });
    }
    return <div className="studio-shell">
        <header className="studio-header">
            <div className="brand"><span className="brand-stamp"><Camera size={23} strokeWidth={1.7} /></span><div><strong>咔咔单词<span className="brand-dot">.</span></strong><span className="eyebrow">VIDEO STUDIO / 视频工作室</span></div></div>
            <div className="header-actions"><span className="local-badge"><span />本地创作</span><Button variant="outline" disabled={!ready || !!busy} onClick={() => run('保存草稿', async () => { await api('project', project); setMessage('草稿已保存在本机'); })}><Save />保存草稿</Button><Button variant="outline" disabled={!project.image || !!busy || !!job} onClick={exportCurrentFrame}><ImageDown />导出当前帧</Button><Button disabled={!!busy || !!job || !exportReady(project)} onClick={() => run('提交导出', async () => { const r = await api<{ id: string }>('render', project); setJob(r.id); setProgress(0); setDownload(''); })}>{job ? <LoaderCircle className="animate-spin" /> : <Download />}{job ? `导出 ${Math.round(progress * 100)}%` : '导出视频'}</Button></div>
        </header>
        <div className="page-intro"><div><span className="eyebrow">EVERYDAY ENGLISH, ONE PHOTO AT A TIME</span><h1>把生活，拍成一堂小课。</h1></div><div className="workflow"><span>01 素材</span><ChevronRight /><span>02 单词</span><ChevronRight /><span>03 成片</span></div></div>
        {(error || message || busy) && <div role={error ? 'alert' : 'status'} className={`notice ${error ? 'notice-error' : ''}`}>{busy ? <LoaderCircle size={16} className="animate-spin" /> : error ? '！' : <Check size={16} />}{error || busy || message}{download && <a className="download-link" href={download}>下载 MP4 →</a>}</div>}
        {ready && project.image && exportIssues.length > 0 && !busy && <div role="status" className="notice notice-warning">导出前还需要：{exportIssues.join('；')}</div>}
        <main className="workspace">
            <aside className="panel materials"><div className="panel-heading"><span className="section-number">01</span><h2>素材与单词</h2><ImagePlus size={17} /></div>
                <fieldset disabled={!!busy || !!job || !ready} className="panel-body">
                    <input ref={input} type="file" multiple accept="image/*,.heic,.heif,video/mp4,video/quicktime,video/webm" className="sr-only" aria-label="上传图片、视频或 Apple 动态照片" onChange={e => { void importFiles(Array.from(e.target.files ?? [])); e.target.value = ''; }} />
                    <button className="upload-zone" onClick={() => input.current?.click()} onDragOver={e => e.preventDefault()} onDrop={e => { e.preventDefault(); if (!busy) void importFiles(Array.from(e.dataTransfer.files)); }}><span className="upload-icon"><ImagePlus size={24} /></span><strong>{project.image || source ? '更换图片或视频' : '放进一张生活的切片'}</strong><span>拖入素材，或点击选择</span><small>图片 / 视频 / Apple 动态照片（同时选择 HEIC + MOV）</small></button>
                    {source && <div className="video-picker"><video key={source} ref={video} src={source} controls preload="metadata" onError={() => setError('无法播放这个视频，请转换为 H.264 MP4 后重试')} onLoadedMetadata={e => { const duration=e.currentTarget.duration; setSourceDuration(duration); if (pendingLivePhotoVideo.current === source) { pendingLivePhotoVideo.current=''; update({ ...project, captureSeconds: duration, introSeconds: 2 }); } }} /><Button variant="secondary" size="sm" onClick={capture}><Camera />使用这一帧</Button><small>{project.video === source ? `快门时刻：${project.captureSeconds.toFixed(2)} 秒 / ${sourceDuration.toFixed(1)} 秒` : `尚未选定拍摄帧 · 视频 ${sourceDuration.toFixed(1)} 秒`}</small></div>}
                    <label className="field-label" htmlFor="title">本期标题</label><input id="title" className="input" value={project.title} maxLength={80} onChange={e => update({ ...project, title: e.target.value })} />
                    {project.captionVariants && <div className="caption-variants" role="radiogroup" aria-label="照片描述风格">
                        {([['serious', '认真', '准确清楚'], ['funny', '搞笑', '轻松有趣'], ['literary', '文艺', '克制有画面感']] as const).map(([style, label, note]) => {
                            const variant = project.captionVariants![style];
                            const active = project.selectedCaptionStyle === style;
                            return <button type="button" role="radio" aria-checked={active} className={active ? 'selected' : ''} key={style} onClick={() => update(selectCaptionVariant(project, style))}>
                                <span><strong>{label}</strong><small>{note}</small></span><p>{variant.caption}</p><em>{variant.captionChinese}</em>
                            </button>;
                        })}
                    </div>}
                    <label className="field-label" htmlFor="caption">最终照片描述 · English</label>
                    <textarea id="caption" className="input caption-input" maxLength={220} value={project.caption} placeholder="AI 按 App 同一识别接口自动生成" onChange={e => update({ ...project, caption: e.target.value, captionAudio: undefined, captionAudioSeconds: undefined, socialCopy: undefined })} />
                    <label className="field-label" htmlFor="captionChinese">最终照片描述 · 中文</label>
                    <textarea id="captionChinese" className="input caption-input" maxLength={220} value={project.captionChinese} placeholder="AI 自动生成对应中文描述" onChange={e => update({ ...project, captionChinese: e.target.value, socialCopy: undefined })} />
                    <p className="hint">AI 识别会通过 App 同一接口生成描述；成片在全部单词读完后展示。</p>
                    <div className="recognize-row"><label htmlFor="count">识别数量</label><select id="count" value={count} onChange={e => setCount(Number(e.target.value))}>{[4, 5, 6, 7, 8, 9, 10].map(n => <option key={n}>{n}</option>)}</select><Button size="sm" disabled={!project.image} onClick={analyze}><Sparkles />{project.words.length ? '重新识别' : 'AI 识别'}</Button></div>
                    {project.words.length > 0 && <p className="hint">重新识别会替换当前词表与配音。</p>}
                    <div className="list-heading"><span>本期词表</span><span className="count-pill">{project.words.length.toString().padStart(2, '0')}</span></div>
                    {!project.words.length && <div className="empty-words"><span>WORDS WILL FIND THEIR PLACE.</span><p>识别照片后，单词会出现在这里。</p></div>}
                    <div className="word-list">{project.words.map((w, index) => <div className={`word-row ${selected === w.id ? 'selected' : ''}`} key={w.id}><button className="word-select" onClick={() => selectWord(w)}><span className="word-no">{String(index+1).padStart(2,'0')}</span><span><strong>{w.english || '未命名单词'}</strong><small>{w.chinese || '添加中文释义'}</small></span>{w.audio && <Volume2 size={13} />}</button><div className="word-actions"><button aria-label={`上移 ${w.english}`} disabled={!index} onClick={() => reorder(index,-1)}><ArrowUp size={13} /></button><button aria-label={`下移 ${w.english}`} disabled={index === project.words.length-1} onClick={() => reorder(index,1)}><ArrowDown size={13} /></button></div></div>)}</div>
                    <Button variant="ghost" size="sm" className="w-full mt-3" disabled={!project.image || project.words.length >= 10} onClick={() => { const w: Word = { id: crypto.randomUUID(), english: 'word', chinese: '', ipa: '', box: { x: .5, y: .6, width: 0, height: 0 } }; update({ ...project, words: [...project.words,w] }); setSelected(w.id); }}><Plus />手动添加单词</Button>
                </fieldset>
            </aside>
            {mode === 'publish' ? <section className="preview-column publish-column">
                <div className="cover-tabs"><Button variant="ghost" onClick={() => setMode('video')}>视频</Button><Button variant="ghost" onClick={() => setMode('cover')}>封面</Button><Button variant="secondary">发布</Button><span>3 PLATFORMS</span></div>
                <PublishPanel project={project} update={update} />
            </section> : mode === 'cover' ? <section className="preview-column">
                <div className="cover-tabs"><Button variant="ghost" onClick={() => setMode('video')}>视频</Button><Button variant="secondary">封面</Button><Button variant="ghost" onClick={() => setMode('publish')}>发布</Button><span>3:4 · 1080 × 1440</span></div>
                <div className="preview-stage"><Player component={Cover} compositionWidth={1080} compositionHeight={1440} durationInFrames={1} fps={30} controls={false} clickToPlay={false} style={{ width: '100%' }} inputProps={{ project, onMove:(id, kind, point) => {
                    setSelected(id); const c = project.cover ?? defaultCover;
                    update({ ...project, cover: { ...c, words: { ...c.words, [id]: { ...(c.words[id] ?? { scale: 1 }), [kind === 'label' ? 'labelCenterOverride' : 'targetCenterOverride']: point } } } });
                } }} /></div>
                <p className="hint">拖动胶囊或圆点调整封面；松手后重新规划引导线。</p>
            </section> : <section className="preview-column"><div className="cover-tabs"><Button variant="secondary" onClick={() => setMode('video')}>视频</Button><Button variant="ghost" onClick={() => { player.current?.pause(); setMode('cover'); }}>封面</Button><Button variant="ghost" onClick={() => { player.current?.pause(); setMode('publish'); }}>发布</Button></div><div className="preview-heading"><span className="eyebrow">THE DAILY FRAME</span><span>9:16 · 1080p · 30 fps</span></div><div className="preview-stage"><div className="preview-tape" /><div className="player-shell">{ready && <Player ref={player} component={Film} inputProps={{ project, onAnnotationMove: moveAnnotation, onAnnotationDragStart: () => player.current?.pause() }} durationInFrames={t.total} compositionWidth={1080} compositionHeight={1920} fps={FPS} controls style={{ width: '100%' }} />}
                {showSafeAreas && <div className="safe-area-overlay" aria-hidden="true">
                    <div className="safe-band safe-band-top" style={{ height: `${project.safeTop/1920*100}%` }}><span>顶部遮挡参考区</span></div>
                    <div className="safe-band safe-band-bottom" style={{ height: `${project.safeBottom/1920*100}%` }}><span>文案 / 导航遮挡参考区</span></div>
                    {project.safeRight > 0 && <div className="safe-band safe-band-right" style={{ width: `${project.safeRight/1080*100}%`, top: `${project.safeTop/1920*100}%`, bottom: `${project.safeBottom/1920*100}%` }} />}
                </div>}
                </div></div><div className="preview-caption"><span className="live-dot" />{(t.total/FPS).toFixed(1)} 秒 <span>拖动胶囊或引导线圆点调整位置</span></div><div className={`timeline-strip ${project.videoTemplate === 'direct' ? 'timeline-direct' : ''}`}>{project.videoTemplate === 'camera' ? <><button onClick={() => player.current?.seekTo(0)}><Camera size={15} /><span>取景</span><small>{project.introSeconds}s</small></button><button onClick={() => player.current?.seekTo(t.intro+6)}><Sparkles size={15} /><span>发现单词</span><small>1.5s</small></button></> : <button onClick={() => player.current?.seekTo(0)}><Sparkles size={15} /><span>完整单词图</span><small>0.5s</small></button>}<button onClick={() => player.current?.seekTo(t.intro+t.reveal)}><Volume2 size={15} /><span>高亮跟读</span><small>{project.words.length} 词</small></button><button onClick={() => player.current?.seekTo(t.captionFrom)}><FilmIcon size={15} /><span>照片句子</span><small>3s</small></button></div></section>}
            {mode === 'publish' ? <aside className="panel settings publish-settings"><div className="panel-heading"><h2>发布助手</h2><Sparkles size={17} /></div><fieldset className="panel-body" disabled={!!busy || !ready}>
                <div className="editor-note"><span>一套内容，三种说法。</span><p>生成时会使用最终照片描述、全部词汇和封面高亮词。</p></div>
                <div className="publish-source"><small>PHOTO NOTE</small><p>{project.captionChinese || '请先完成 AI 识别并选定照片描述。'}</p><div>{project.words.map(word => <span key={word.id}>{word.english}</span>)}</div></div>
                <Button className="w-full mt-4" disabled={!project.caption.trim() || !project.words.length} onClick={generatePublishingCopy}><Sparkles />{project.socialCopy ? '重新生成三平台文案' : '生成三平台文案'}</Button>
                <p className="hint">重新生成会替换三个平台当前的编辑内容。文案只保存在本地草稿，不会自动发布。</p>
            </fieldset></aside> : mode === 'cover' ? <aside className="panel settings"><div className="panel-heading"><h2>学习卡片封面</h2></div><fieldset className="panel-body" disabled={!!busy || !ready}>
                <p className="hint">完整照片 · 全部单词<br />尺寸与位置仅用于封面，随草稿保存。</p>
                <label className="range-field"><span>全部胶囊 <strong>{Math.round((project.cover?.scale ?? 1)*100)}%</strong></span><input aria-label="全部胶囊大小" type="range" min=".6" max="1.6" step=".01" value={project.cover?.scale ?? 1} onChange={e => update({ ...project, cover: { ...(project.cover ?? defaultCover), scale: Number(e.target.value) } })} /></label>
                {word ? <label className="range-field"><span>{word.english} <strong>{Math.round((project.cover?.words[word.id]?.scale ?? 1)*100)}%</strong></span><input aria-label="当前胶囊大小" type="range" min=".75" max="1.5" step=".01" value={project.cover?.words[word.id]?.scale ?? 1} onChange={e => { const c = project.cover ?? defaultCover; update({ ...project, cover: { ...c, words: { ...c.words, [word.id]: { ...c.words[word.id], scale: Number(e.target.value) } } } }); }} /></label> : <p className="hint">选择左侧单词，可单独调整大小。</p>}
                <div className="cover-highlight-picker"><h3>高亮单词</h3><p className="hint">可多选，与视频一致：亮黄胶囊、加粗描边和放大效果，引导线同步高亮。</p>
                    <div className="cover-highlight-list">{project.words.map(w => <label key={w.id}><input type="checkbox" checked={project.cover?.words[w.id]?.highlighted ?? false} onChange={e => {
                        const c = project.cover ?? defaultCover;
                        update({ ...project, cover: { ...c, words: { ...c.words, [w.id]: { ...(c.words[w.id] ?? { scale: 1 }), highlighted: e.target.checked } } } });
                    }} /><span>{w.english}</span></label>)}</div>
                    <Button variant="ghost" size="sm" disabled={!project.words.some(w => project.cover?.words[w.id]?.highlighted)} onClick={() => {
                        const c = project.cover ?? defaultCover;
                        update({ ...project, cover: { ...c, words: Object.fromEntries(Object.entries(c.words).map(([id, value]) => [id, { ...value, highlighted: false }])) } });
                    }}>清除高亮</Button>
                </div>
                <Button variant="outline" className="w-full" onClick={() => { const c = project.cover ?? defaultCover; update({ ...project, cover: { ...c, words: Object.fromEntries(Object.entries(c.words).map(([id, value]) => [id, { scale: value.scale, highlighted: value.highlighted }])) } }); }}>恢复视频位置</Button>
                {coverConflicts.length > 0 && <p role="alert" className="cover-conflict">以下胶囊重叠或超出安全边距：{project.words.filter(w => coverConflicts.includes(w.id)).map(w => w.english).join('、')}。请缩小或移动后再导出。</p>}
                <Button className="w-full mt-4" disabled={!project.image || !project.words.length || project.words.some(w => !w.english.trim()) || coverConflicts.length > 0} onClick={() => run('导出封面', async () => { const result = await api<{ file: string }>('render-cover', { project }); const a = document.createElement('a'); a.href = result.file; a.download = 'kakaword-cover.png'; a.click(); setMessage('封面已导出'); })}><ImageDown />导出封面 PNG</Button>
            </fieldset></aside> : <aside className="panel settings"><div className="panel-heading"><span className="section-number">02</span><h2>校对与节奏</h2><Volume2 size={17} /></div><fieldset disabled={!!busy || !!job || !ready} className="panel-body">
                <div className="editor-note"><span>一张照片，一点新发现。</span><p>画面保持安静，让正在读的单词亮起来。</p></div>
                {word ? <><div className="edit-heading"><span>当前单词</span><Button variant="ghost" size="icon" aria-label="删除当前单词" onClick={() => { update({ ...project, words: project.words.filter(w => w.id !== selected) }); setSelected(''); }}><Trash2 /></Button></div><label className="field-label" htmlFor="english">英文</label><input id="english" className="input word-input" maxLength={60} value={word.english} onChange={e => editWord(changeEnglish(word, e.target.value))} /><label className="field-label" htmlFor="chinese">中文释义</label><input id="chinese" className="input" maxLength={60} value={word.chinese} onChange={e => editWord({ chinese: e.target.value })} /><label className="field-label" htmlFor="ipa">音标</label><input id="ipa" className="input" maxLength={80} value={word.ipa} onChange={e => editWord({ ipa: e.target.value })} /><label className="field-label">单词胶囊位置</label><div className="position-grid">{(['x','y'] as const).map((key,i) => <label key={key}><span>{['横向','纵向'][i]} <small>{(selectedCenter[key]*100).toFixed(1)}%</small></span><input type="range" min="0" max="100" step="0.1" value={selectedCenter[key]*100} onChange={e => editWord({ labelCenterOverride: { ...selectedCenter, [key]: Number(e.target.value)/100 } })} /></label>)}</div><label className="field-label">引导线终点位置</label><div className="position-grid">{(['x','y'] as const).map((key,i) => <label key={key}><span>{['横向','纵向'][i]} <small>{(selectedTarget[key]*100).toFixed(1)}%</small></span><input type="range" min="0" max="100" step="0.1" value={selectedTarget[key]*100} onChange={e => editWord({ targetCenterOverride: { ...selectedTarget, [key]: Number(e.target.value)/100 } })} /></label>)}</div><Button variant="ghost" size="sm" className="w-full mt-2" disabled={!word.labelCenterOverride && !word.targetCenterOverride} onClick={() => editWord({ labelCenterOverride: undefined, targetCenterOverride: undefined })}>恢复自动位置</Button>{word.audio && <audio className="word-audio" src={word.audio} controls />}</> : <div className="select-hint">选择左侧单词，校对文字并调整胶囊和引导线。</div>}
                <div className="settings-divider" /><h3>平台安全留白</h3>
                <label className="safe-toggle"><input type="checkbox" checked={showSafeAreas} onChange={e => setShowSafeAreas(e.target.checked)} />显示遮挡参考区（仅预览）</label>
                {([['safeTop', '顶部', 120, 280], ['safeBottom', '底部', 240, 480], ['safeRight', '右侧按钮区', 0, 160]] as const).map(([key, title, min, max]) => <label className="range-field" key={key}><span>{title}留白 <strong>{project[key]} px</strong></span><input type="range" min={min} max={max} step="20" value={project[key]} onChange={e => update({ ...project, [key]: Number(e.target.value) })} /></label>)}
                <p className="hint">文字和标签会避开留白区域。遮挡参考区不进入成片；可按小红书 / 抖音的发布预览调整。</p>
                <div className="settings-divider" /><h3>视频模板</h3><div className="template-picker"><button type="button" className={project.videoTemplate === 'direct' ? 'selected' : ''} onClick={() => update({ ...project, videoTemplate: 'direct' })}><strong>直接学习</strong><span>第一帧展示全部单词，0.5 秒后开始朗读</span></button><button type="button" className={project.videoTemplate === 'camera' ? 'selected' : ''} onClick={() => update({ ...project, videoTemplate: 'camera' })}><strong>拍照识别</strong><span>保留动态取景、快门和识别过渡</span></button></div><h3>播放节奏</h3><label className="field-label" htmlFor="voiceId">MiniMax 配音音色</label><select id="voiceId" className="input" value={project.voiceId} onChange={e => update({ ...project, voiceId: e.target.value as Project['voiceId'], captionAudio: undefined, captionAudioSeconds: undefined, words: project.words.map(word => ({ ...word, audio: undefined, audioSeconds: undefined })) })}>{voiceOptions.map(voice => <option key={voice.id} value={voice.id}>{voice.label} · {voice.id}</option>)}</select><label className="range-field"><span>配音语速 <strong>{project.speechSpeed.toFixed(2)}×</strong></span><input type="range" min="0.5" max="2" step="0.05" value={project.speechSpeed} onChange={e => update({ ...project, speechSpeed: Number(e.target.value), captionAudio: undefined, captionAudioSeconds: undefined, words: project.words.map(word => ({ ...word, audio: undefined, audioSeconds: undefined })) })} /></label><p className="hint">更换音色或语速后需要重新生成全部配音。</p>{project.videoTemplate === 'camera' && <label className="range-field"><span>开头取景（视频末尾） <strong>{project.introSeconds.toFixed(1)} 秒</strong><input type="range" min="0.5" max="5" step="0.1" value={project.introSeconds} onChange={e => update({ ...project, introSeconds: Number(e.target.value) })} /></span></label>}<label className="range-field"><span>跟读留白 <strong>{project.pauseSeconds.toFixed(1)} 秒</strong></span><input type="range" min="0" max="3" step="0.1" value={project.pauseSeconds} onChange={e => update({ ...project, pauseSeconds: Number(e.target.value) })} /></label>
                <Button variant="secondary" className="w-full mt-4" disabled={!project.caption.trim() || !project.words.length || project.words.some(w => !w.english.trim())} onClick={speech}><Volume2 />生成全部配音</Button><p className="hint">会生成每个单词和照片英文句子的配音。修改英文后需重新生成。</p><Button variant="outline" className="w-full mt-2" disabled={!project.image} onClick={() => { player.current?.seekTo(0); player.current?.play(); }}><Play />从头预览</Button>
            </fieldset></aside>}
        </main><footer className="studio-footer"><span>KAKAWORD · CREATIVE NOTEBOOK</span><span>每日一拍，每日一词。让学习留在生活里。</span></footer>
    </div>;
}
