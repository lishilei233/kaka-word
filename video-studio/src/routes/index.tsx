import { createFileRoute } from '@tanstack/react-router';
import { ProjectLibrary } from '../components/ProjectLibrary';
export const Route = createFileRoute('/')({ component: ProjectLibrary });
