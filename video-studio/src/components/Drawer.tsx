import { useEffect, type ReactNode } from 'react';
import { X } from 'lucide-react';

export function Drawer({ title, open, onClose, children }: { title: string; open: boolean; onClose: () => void; children: ReactNode }) {
    useEffect(() => {
        if (!open) return;
        const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape') onClose(); };
        document.addEventListener('keydown', onKey);
        return () => document.removeEventListener('keydown', onKey);
    }, [open, onClose]);
    if (!open) return null;
    return <div className="drawer-layer" role="presentation">
        <button className="drawer-backdrop" aria-label="关闭窗口" onClick={onClose} />
        <aside className="drawer" role="dialog" aria-modal="true" aria-label={title}>
            <header className="drawer-header"><h2>{title}</h2><button className="drawer-close" aria-label="关闭" onClick={onClose}><X size={18} /></button></header>
            <div className="drawer-body">{children}</div>
        </aside>
    </div>;
}
