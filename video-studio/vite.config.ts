import { defineConfig } from 'vite';
import { tanstackStart } from '@tanstack/react-start/plugin/vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { fileURLToPath } from 'node:url';

export default defineConfig({
    plugins: [tailwindcss(), tanstackStart(), react()],
    // Remotion's renderer/bundler load native Node modules; never prebundle them for browsers.
    optimizeDeps: { exclude: ['@remotion/bundler', '@remotion/renderer'] },
    ssr: { external: ['@remotion/bundler', '@remotion/renderer'] },
    resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
    server: {
        host: '127.0.0.1', port: 3210, strictPort: true,
    },
});
