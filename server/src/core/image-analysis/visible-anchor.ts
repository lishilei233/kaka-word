import type { AnalyzeResult } from "./types.js";

type ObjectResult = AnalyzeResult["objects"][number];
type Point = { x: number; y: number };

export function validVisibleAnchor(point: Point | undefined, box: ObjectResult["box"]): point is Point {
  return !!point && Number.isFinite(point.x) && Number.isFinite(point.y)
    && point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1
    && point.x >= box.x && point.x <= box.x + box.width
    && point.y >= box.y && point.y <= box.y + box.height;
}

export function normalizeVisibleAnchor(object: ObjectResult): ObjectResult {
  const valid = validVisibleAnchor(object.anchor, object.box) && object.anchorSource !== "centerFallback";
  return {
    ...object,
    anchor: valid ? object.anchor : { x: object.box.x + object.box.width / 2, y: object.box.y + object.box.height / 2 },
    anchorSource: valid ? "ai" : "centerFallback",
    anchorNeedsReview: !valid,
  };
}

// A smaller overlapping box is only a suspicion of occlusion, never a pixel mask.
export function markSuspiciousAnchors(objects: ObjectResult[]): ObjectResult[] {
  return objects.map((object) => ({
    ...object,
    anchorNeedsReview: object.anchorNeedsReview || objects.some((other) =>
      other.id !== object.id && other.box.width * other.box.height < object.box.width * object.box.height * 0.7
      && validVisibleAnchor(object.anchor, other.box)),
  }));
}
