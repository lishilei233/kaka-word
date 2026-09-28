import { getImageDimensions as pixelDimensions } from '../../../server/src/utils/image-dimensions.ts';

// JPEG frame dimensions describe stored pixels, before EXIF display rotation.
export function getImageDimensions(bytes: Uint8Array) {
    const dimensions = pixelDimensions(bytes);
    if (!dimensions || bytes[0] !== 0xff || bytes[1] !== 0xd8) return dimensions;
    let offset = 2;
    while (offset + 4 <= bytes.length && bytes[offset] === 0xff) {
        const marker = bytes[offset + 1];
        if (marker === 0xda || marker === 0xd9) break;
        const length = (bytes[offset + 2] << 8) | bytes[offset + 3];
        const end = offset + 2 + length;
        if (length < 2 || end > bytes.length) break;
        const data = bytes.subarray(offset + 4, end);
        if (marker === 0xe1 && data.length >= 14 && data[0] === 69 && data[1] === 120 && data[2] === 105 && data[3] === 102 && data[4] === 0 && data[5] === 0) {
            const tiff = new DataView(data.buffer, data.byteOffset + 6, data.length - 6);
            const order = tiff.getUint16(0);
            const little = order === 0x4949;
            if ((little || order === 0x4d4d) && tiff.getUint16(2, little) === 42) {
                const ifd = tiff.getUint32(4, little);
                if (ifd >= 8 && ifd + 2 <= tiff.byteLength) {
                    const count = tiff.getUint16(ifd, little);
                    for (let i = 0; i < count; i++) {
                        const entry = ifd + 2 + i * 12;
                        if (entry + 12 > tiff.byteLength) break;
                        if (tiff.getUint16(entry, little) !== 0x0112 || tiff.getUint16(entry + 2, little) !== 3 || tiff.getUint32(entry + 4, little) !== 1) continue;
                        const orientation = tiff.getUint16(entry + 8, little);
                        return orientation >= 5 && orientation <= 8
                            ? { width: dimensions.height, height: dimensions.width } : dimensions;
                    }
                }
            }
        }
        offset = end;
    }
    return dimensions;
}
