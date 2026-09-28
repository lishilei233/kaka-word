import { test } from 'node:test';
import assert from 'node:assert/strict';
import { uploadApplePhoto } from './media.ts';

test('Apple photos use decoded dimensions and normalized pixels instead of converter dimensions', async (t) => {
    for (const [width, height] of [[3024, 4032], [4032, 3024]]) {
        await t.test(`${width} x ${height}`, async (t) => {
            const originalGlobals = new Map(['Image', 'HTMLVideoElement', 'document', 'fetch'].map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
            t.after(() => {
                for (const [key, descriptor] of originalGlobals) {
                    if (descriptor) Object.defineProperty(globalThis, key, descriptor);
                    else Reflect.deleteProperty(globalThis, key);
                }
            });
            const convertedUrl = '/studio-api/assets/converted.jpg';
            const normalizedUrl = '/studio-api/assets/normalized.jpg';
            const normalizedBlob = new Blob(['normalized pixels'], { type: 'image/jpeg' });
            let decoded = false;
            let drawn = false;
            let uploads = 0;
            class DecodedImage {
                src = '';
                naturalWidth = 0;
                naturalHeight = 0;
                async decode() {
                    assert.equal(this.src, convertedUrl);
                    this.naturalWidth = width;
                    this.naturalHeight = height;
                    decoded = true;
                }
            }
            const canvas = {
                width: 0, height: 0,
                getContext: () => ({ drawImage(image: DecodedImage, x: number, y: number, w: number, h: number) {
                    assert.ok(decoded);
                    assert.equal(image.naturalWidth / image.naturalHeight, w / h);
                    assert.equal(x, 0); assert.equal(y, 0);
                    drawn = true;
                } }),
                toBlob(callback: BlobCallback, type: string) {
                    assert.ok(drawn);
                    assert.equal(type, 'image/jpeg');
                    callback(normalizedBlob);
                },
            };
            Object.assign(globalThis, {
                Image: DecodedImage,
                HTMLVideoElement: class {},
                document: { createElement: () => canvas },
                fetch: async (url: string, options: RequestInit) => {
                    uploads++;
                    if (uploads === 1) {
                        assert.equal(url, '/studio-api/upload?ext=heic');
                        // Simulate stored dimensions that disagree with EXIF-oriented display.
                        return Response.json({ url: convertedUrl, imageWidth: height, imageHeight: width });
                    }
                    assert.equal(url, '/studio-api/upload?ext=jpg');
                    assert.equal(options.body, normalizedBlob);
                    return Response.json({ url: normalizedUrl });
                },
            });
            const result = await uploadApplePhoto(new Blob(['HEIC']), 'heic');
            assert.equal(uploads, 2);
            assert.equal(result.url, normalizedUrl);
            assert.equal(result.imageWidth / result.imageHeight, width / height);
            assert.equal(Math.max(result.imageWidth, result.imageHeight), 1800);
            assert.equal(result.imageWidth, canvas.width);
            assert.equal(result.imageHeight, canvas.height);
        });
    }
});
