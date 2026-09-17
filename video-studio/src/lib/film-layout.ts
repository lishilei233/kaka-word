import { sceneWords, type Project } from './project';
export type Rect = { x: number; y: number; width: number; height: number };
export const FILM_WIDTH = 540;
export const FILM_HEIGHT = 960;
export const SCENE_CARD_HEIGHT = 44;
export const SCENE_CARD_GAP = 6;
export const WORD_DETAIL_HEIGHT = 110;
// Keep a slim paper edge around the photo: 10 logical points = 20 exported px.
export const PHOTO_SIDE_MARGIN = 10;
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
    const photoWidth = FILM_WIDTH - PHOTO_SIDE_MARGIN * 2;
    const photoHeight = photoWidth / aspect;
    // Safe areas are soft constraints for the result card. Keep the original
    // Keep the photo at the original near-full-width size and move tall photos
    // upward before allowing the soft safe-area overlap.
    const photoTop = Math.min(top, Math.max(0, FILM_HEIGHT - photoHeight));
    const photo = { x: PHOTO_SIDE_MARGIN, y: photoTop, width: photoWidth, height: photoHeight };
    const sceneHeight = sceneWords(p.words).length ? SCENE_CARD_HEIGHT : 0;
    const sceneTop = sceneHeight ? photo.y + photo.height - sceneHeight - 12 : photo.y + photo.height;
    const sceneLeft = photo.x + 12;
    const sceneWidth = photo.width - 24;
    const belowPhoto = photo.y + photo.height + 16;
    const wordTop = belowPhoto + WORD_DETAIL_HEIGHT <= FILM_HEIGHT - 12 ? belowPhoto : Math.min(FILM_HEIGHT - WORD_DETAIL_HEIGHT - 12, Math.max(12, sceneTop - WORD_DETAIL_HEIGHT - 12));
    const descriptionTop = belowPhoto + 140 <= FILM_HEIGHT - 12 ? belowPhoto : Math.min(FILM_HEIGHT - 152, Math.max(12, sceneTop - 152));
    const closingTop = Math.min(descriptionTop + 154, FILM_HEIGHT - WORD_DETAIL_HEIGHT - 12);
    // CameraView.swift covers the full screen and uses resizeAspect for the sensor image.
    const camera = { x: 0, y: 0, width: FILM_WIDTH, height: FILM_HEIGHT };
    return { top, bottom, textLeft, textRight, wordTop, descriptionTop, closingTop, sceneTop, sceneLeft, sceneWidth, sceneHeight,
        wordDetailHeight: WORD_DETAIL_HEIGHT, wordOverPhoto: wordTop < photo.y + photo.height, descriptionOverPhoto: descriptionTop < photo.y + photo.height, photo, camera,
        photoImage: photo, cameraImage: fitImage(camera, aspect), shutterTop: bottom - 104 };
}
