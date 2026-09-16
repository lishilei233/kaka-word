import { createFileRoute } from '@tanstack/react-router';

export const Route = createFileRoute('/studio-api/$')({
    server: {
        handlers: {
            GET: async ({ request }) => (await import('../server/api.server')).handleStudioRequest(request),
            POST: async ({ request }) => (await import('../server/api.server')).handleStudioRequest(request),
        },
    },
});
