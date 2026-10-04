import { bundle } from '@remotion/bundler';
import { resolve } from 'node:path';

/** Share source-module resolution across video, cover and still exports. */
export function bundleStudioVideo() {
    return bundle({
        entryPoint: resolve('src/video/Root.tsx'),
        webpackOverride: config => ({
            ...config,
            resolve: {
                ...config.resolve,
                // Server sources use .js imports for Node ESM. During a source
                // bundle these modules are still .ts files, as in Vite/TypeScript.
                extensionAlias: { ...config.resolve?.extensionAlias, '.js': ['.js', '.ts', '.tsx'] },
            },
        }),
    });
}
