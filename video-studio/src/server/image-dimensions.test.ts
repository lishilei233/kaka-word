import { test } from 'node:test';
import assert from 'node:assert/strict';
import { getImageDimensions } from './image-dimensions.ts';

function jpeg(orientation: number, little: boolean) {
    const exif = Buffer.alloc(32);
    exif.write('Exif\0\0');
    const tiff = new DataView(exif.buffer, exif.byteOffset + 6, 26);
    tiff.setUint16(0, little ? 0x4949 : 0x4d4d);
    tiff.setUint16(2, 42, little);
    tiff.setUint32(4, 8, little);
    tiff.setUint16(8, 1, little);
    tiff.setUint16(10, 0x0112, little);
    tiff.setUint16(12, 3, little);
    tiff.setUint32(14, 1, little);
    tiff.setUint16(18, orientation, little);
    return Buffer.concat([Buffer.from([255, 216, 255, 225, 0, 34]), exif,
        Buffer.from([255, 192, 0, 11, 8, 0, 3, 0, 4, 1, 1, 17, 0, 255, 217])]);
}

test('JPEG display dimensions respect all EXIF orientations in either byte order', () => {
    for (const little of [true, false]) for (let orientation = 1; orientation <= 8; orientation++) {
        assert.deepEqual(getImageDimensions(jpeg(orientation, little)), orientation >= 5
            ? { width: 3, height: 4 } : { width: 4, height: 3 });
    }
});

test('invalid EXIF offsets preserve pixel dimensions without throwing', () => {
    const bytes = jpeg(6, true);
    bytes.writeUInt32LE(0xffffffff, 16);
    assert.deepEqual(getImageDimensions(bytes), { width: 4, height: 3 });
});
