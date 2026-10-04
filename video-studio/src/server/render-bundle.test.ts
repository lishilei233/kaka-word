import test from 'node:test';
import assert from 'node:assert/strict';
import { stat, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { bundleStudioVideo } from './render-bundle';

test('export bundle compiles the actual video and cover with shared server TypeScript imports', async t => {
    const serveUrl = await bundleStudioVideo();
    t.after(() => rm(serveUrl, { recursive: true, force: true }));
    assert.ok((await stat(join(serveUrl, 'index.html'))).size > 0);
    assert.ok((await stat(join(serveUrl, 'bundle.js'))).size > 0);
});
