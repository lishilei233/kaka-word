import type { Project } from './project';
export type Rect = { x: number; y: number; width: number; height: number };
export const FILM_WIDTH = 540;
export const FILM_HEIGHT = 960;
function fitImage(frame: Rect, aspect: number): Rect {
    const width = Math.min(frame.width, frame.height * aspect);
    const height = width / aspect;
    return { x: frame.x + (frame.width - width) / 2, y: frame.y + (frame.height - height) / 2, width, height };
}
export function filmLayout(p: Project) {
    // Logical points are half the exported 1080 × 1920 pixels.
    const top = p.safeTop / 2, bottom = FILM_HEIGHT - p.safeBottom / 2;
    const textLeft = 24, textRight = FILM_WIDTH - p.safeRight / 2 - 20;
    const aspect = p.imageWidth / p.imageHeight;
    const photoTop = top;
    const photoWidth = FILM_WIDTH - 40;
    const photoHeight = photoWidth / aspect;
    const photo = { x: 20, y: photoTop, width: photoWidth, height: photoHeight };
    const descriptionTop = photo.y + photo.height + 16;
    const wordTop = descriptionTop;
    const closingTop = descriptionTop + 154;
    // CameraView.swift covers the full screen and uses resizeAspect for the sensor image.
    const camera = { x: 0, y: 0, width: FILM_WIDTH, height: FILM_HEIGHT };
    return { top, bottom, textLeft, textRight, wordTop, descriptionTop, closingTop, photo, camera,
        photoImage: photo, cameraImage: fitImage(camera, aspect), shutterTop: bottom - 104 };
}
