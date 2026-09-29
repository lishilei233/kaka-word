import { createFileRoute, Link } from '@tanstack/react-router';
import { useEffect, useState } from 'react';
import { Studio } from '../components/Studio';
import { api } from '../lib/media';
import { projectRecordSchema, type ProjectRecord } from '../lib/project-record';
import { Button } from '../components/ui/button';

export const Route = createFileRoute('/projects/$projectId')({ component: ProjectPage });
function ProjectPage() {
    const { projectId } = Route.useParams();
    return <ProjectLoader key={projectId} id={projectId} />;
}
function ProjectLoader({ id }: { id: string }) {
    const [record, setRecord] = useState<ProjectRecord>();
    const [error, setError] = useState('');
    const [attempt, setAttempt] = useState(0);
    useEffect(() => {
        let cancelled = false;
        setError('');
        api<ProjectRecord>(`projects/${id}`).then(value => { if (!cancelled) setRecord(projectRecordSchema.parse(value)); }).catch(e => { if (!cancelled) setError(e.message); });
        return () => { cancelled = true; };
    }, [id, attempt]);
    if (record) return <Studio initialRecord={record} />;
    return <main className="studio-shell library-empty"><h1>{error ? '暂时无法打开作品' : '正在读取作品…'}</h1>{error && <><p role="alert">{error}</p><Button onClick={() => setAttempt(n => n + 1)}>重试</Button></>}<Link to="/">返回作品</Link></main>;
}
