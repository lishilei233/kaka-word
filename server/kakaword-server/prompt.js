export function learningObjectPrompt(maxObjects) {
    return `You are an English vocabulary learning assistant. Analyze the image and return ONLY valid JSON.

Find up to ${maxObjects} visible, useful, concrete everyday objects that are good for a Chinese learner of English. Prefer foreground objects and common nouns. Ignore walls, floors, tiny background details, duplicate objects, people, text in the image, and uncertain objects.

Return exactly this shape:
{
  "imageWidth": number,
  "imageHeight": number,
  "objects": [
    {
      "id": "obj_01",
      "english": "mug",
      "chinese": "杯子",
      "ipa": "/mʌɡ/",
      "confidence": 0.94,
      "box": { "x": 0.58, "y": 0.42, "width": 0.22, "height": 0.25 },
      "anchor": { "x": 0.69, "y": 0.54 },
      "example": "This is a mug."
    }
  ]
}

Coordinates must be normalized from 0 to 1, with box x/y as the top-left corner. The box must tightly contain the actual object. anchor must be a visible point on the object's own pixels, not merely the center of its box. For hollow, separated, thin, or partially occluded objects, choose an unmistakable visible part. Nearby objects such as a curtain and window must have clearly different anchors: curtain on fabric, window on glass or frame. Keep the English word natural and singular. Use simplified Chinese. Do not include markdown fences or commentary.`;
}
export function qwenLearningObjectPrompt(maxObjects) {
    return `You are an English vocabulary learning assistant. Analyze the image and output JSON only.

Find 3 to ${maxObjects} visible, useful, concrete everyday objects for a Chinese learner of English. Prefer prominent foreground objects. Ignore walls, floors, tiny background details, duplicate objects, people, text in the image, and uncertain objects.

Return exactly this JSON shape:
{
  "objects": [
    {
      "id": "obj_01",
      "english": "mug",
      "chinese": "杯子",
      "ipa": "/mʌɡ/",
      "confidence": 0.94,
      "bbox": [580, 420, 800, 700],
      "anchor": [690, 550],
      "example": "This is a mug."
    }
  ]
}

bbox must be [x1, y1, x2, y2] relative to the original image and normalized to integer coordinates from 0 to 999. anchor must be [x, y] in the same 0 to 999 coordinate system. The box must tightly contain the actual object. The anchor must lie on clearly visible pixels belonging to that object, not simply at the bbox center. For hollow, separated, thin, or partially occluded objects, choose an unmistakable visible part. Do not confuse nearby objects: for curtain place anchor on curtain fabric; for window place anchor on glass or frame. Use a natural singular English noun, simplified Chinese, and a short beginner-friendly English example. Do not output markdown or commentary.`;
}
export function extractJson(text) {
    const cleaned = text.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "");
    const start = cleaned.indexOf("{");
    const end = cleaned.lastIndexOf("}");
    if (start < 0 || end <= start)
        throw new Error("Vision provider returned no JSON object");
    return JSON.parse(cleaned.slice(start, end + 1));
}
