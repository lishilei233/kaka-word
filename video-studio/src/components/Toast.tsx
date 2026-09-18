import { Check, LoaderCircle, TriangleAlert, X } from 'lucide-react';
import { useEffect, useState } from 'react';

export type ToastKind = 'loading' | 'success' | 'error' | 'warning';
export function Toast({ kind, text, download, persistent = false, onDismiss }: { kind?: ToastKind; text?: string; download?: string; persistent?: boolean; onDismiss?: () => void }) {
    const [visible, setVisible] = useState(Boolean(kind && text));
    useEffect(() => {
        setVisible(Boolean(kind && text));
        if (!kind || !text || persistent || kind === 'loading') return;
        const timer = window.setTimeout(() => { setVisible(false); onDismiss?.(); }, kind === 'error' ? 5600 : 3600);
        return () => window.clearTimeout(timer);
    }, [kind, text, persistent]);
    if (!visible || !kind || !text) return null;
    const Icon = kind === 'loading' ? LoaderCircle : kind === 'error' ? TriangleAlert : kind === 'warning' ? TriangleAlert : Check;
    return <div className="toast-layer"><div className={`toast toast-${kind}`} role={kind === 'error' ? 'alert' : 'status'} aria-live={kind === 'error' ? 'assertive' : 'polite'}>
        <Icon size={17} className={kind === 'loading' ? 'animate-spin' : undefined} />
        <span>{text}</span>
        {download && <a className="toast-download" href={download}>下载 MP4 →</a>}
        {kind !== 'loading' && <button type="button" className="toast-close" aria-label="关闭提示" onClick={() => { setVisible(false); onDismiss?.(); }}><X size={15} /></button>}
    </div></div>;
}
