import type { AnalyzeResult } from "./types.js";

export const minimumObjectArea = 0.005;
export const minimumObjectSide = 0.02;

// Allow only floating-point rounding at an exact threshold.
const thresholdTolerance = 1e-12;

export function hasRecognizableSize(object: Pick<AnalyzeResult["objects"][number], "box">): boolean {
  const { x, y, width, height } = object.box;
  if (![x, y, width, height].every(Number.isFinite) || width <= 0 || height <= 0) return false;
  const visibleWidth = Math.max(0, Math.min(1, x + width) - Math.max(0, x));
  const visibleHeight = Math.max(0, Math.min(1, y + height) - Math.max(0, y));
  return visibleWidth + thresholdTolerance >= minimumObjectSide
    && visibleHeight + thresholdTolerance >= minimumObjectSide
    && visibleWidth * visibleHeight + thresholdTolerance >= minimumObjectArea;
}

export const objectSizeInstruction = `Prioritize objects with clear boundaries and reliably identifiable locations. Skip distant tiny objects, blurry objects, and heavily occluded objects. Only include an object if its tight bounding box, intersected with the image, covers at least ${minimumObjectArea * 100}% of the whole image area and its width and height each cover at least ${minimumObjectSide * 100}% of the corresponding image dimension. These are minimums, not a reason to include an unclear object. Return fewer objects, or an empty objects array, when necessary. Never enlarge a box or combine separate objects to meet these thresholds or fill the object count.`;
