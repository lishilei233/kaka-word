import type { CaptionStyle } from "./types.js";

export function learningObjectPrompt(
  maxObjects: number,
  captionStyle: CaptionStyle,
  masteredWords: string[] = [],
): string {
  const captionInstruction = captionStyle === "funny"
    ? "Write one short, playful, friendly English sentence about the whole image. Gentle visual humor is welcome, but never mock people or infer sensitive traits."
    : "Write one short, accurate, natural English sentence describing the whole image.";
  const captionExample = captionStyle === "funny"
    ? "The mug is patiently waiting for its next coffee mission."
    : "A mug sits beside an open book.";
  const masteryInstruction = masteredWordsInstruction(masteredWords);
  return `You are an English vocabulary learning assistant. Analyze the image and return ONLY valid JSON.

Find up to ${maxObjects} clearly visible, concrete everyday objects whose locations and boundaries can be identified reliably. Include every such object that is useful for a Chinese learner of English, even if it is in the background or less prominent. An object may still be included when its presence and location are clear but its precise name is uncertain. Ignore only heavily occluded objects, objects too tiny or unclear to locate reliably, duplicate objects, people, and text in the image. Do not omit a clearly visible object merely because it is not the main subject or because multiple similar names are plausible.
${masteryInstruction}

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
      "example": "This is a mug.",
      "exampleChinese": "这是一个杯子。",
      "confirmationStatus": "confirmed"
    }
  ],
  "caption": ${JSON.stringify(captionExample)},
  "captionChinese": "一个杯子、一本书和一盆植物摆在一起。"
}

Coordinates must be normalized from 0 to 1, with box x/y as the top-left corner. The box must tightly contain the actual object. anchor must be a visible point on the object's own pixels, not merely the center of its box. For hollow, separated, thin, or partially occluded objects, choose an unmistakable visible part. Nearby objects such as a curtain and window must have clearly different anchors: curtain on fabric, window on glass or frame. Keep the English word natural and singular. Use simplified Chinese for chinese and exampleChinese, and translate each English example naturally.

First decide whether the object itself exists and can be located reliably. If not, skip it. If it can be located and its precise name is clear, set confirmationStatus to "confirmed" and omit candidates. If it can be located but 2 or more similar names are genuinely plausible, keep the object, set confirmationStatus to "needsConfirmation", and return 2 or 3 candidates ordered most likely first. Each candidate must contain english, chinese, ipa, example, and exampleChinese. The top-level vocabulary fields must exactly match the first candidate. Do not invent weak alternatives. Never output "userConfirmed"; the app reserves it for a learner's choice.

${captionInstruction} The caption must be exactly one beginner-friendly sentence and no more than 24 words. Translate the caption into one natural, short simplified-Chinese sentence in captionChinese. Do not include markdown fences or commentary.`;
}

export function qwenLearningObjectPrompt(
  maxObjects: number,
  captionStyle: CaptionStyle,
  masteredWords: string[] = [],
): string {
  const captionInstruction = captionStyle === "funny"
    ? "Write one short, playful, friendly English sentence about the whole image. Gentle visual humor is welcome, but never mock people or infer sensitive traits."
    : "Write one short, accurate, natural English sentence describing the whole image.";
  const captionExample = captionStyle === "funny"
    ? "The mug is patiently waiting for its next coffee mission."
    : "A mug sits beside an open book.";
  const masteryInstruction = masteredWordsInstruction(masteredWords);
  return `You are an English vocabulary learning assistant. Analyze the image and output JSON only.

Find up to ${maxObjects} clearly visible, concrete everyday objects whose locations and boundaries can be identified reliably. Include every such object that is useful for a Chinese learner of English, even if it is in the background or less prominent. An object may still be included when its presence and location are clear but its precise name is uncertain. Ignore only heavily occluded objects, objects too tiny or unclear to locate reliably, duplicate objects, people, and text in the image. Do not omit a clearly visible object merely because it is not the main subject or because multiple similar names are plausible.
${masteryInstruction}

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
      "example": "This is a mug.",
      "exampleChinese": "这是一个杯子。",
      "confirmationStatus": "confirmed"
    }
  ],
  "caption": ${JSON.stringify(captionExample)},
  "captionChinese": "一个杯子、一本书和一盆植物摆在一起。"
}

bbox must be [x1, y1, x2, y2] relative to the original image and normalized to integer coordinates from 0 to 999. anchor must be [x, y] in the same 0 to 999 coordinate system. The box must tightly contain the actual object. The anchor must lie on clearly visible pixels belonging to that object, not simply at the bbox center. For hollow, separated, thin, or partially occluded objects, choose an unmistakable visible part. Do not confuse nearby objects: for curtain place anchor on curtain fabric; for window place anchor on glass or frame. Use a natural singular English noun, simplified Chinese, a short beginner-friendly English example, and its natural simplified-Chinese translation in exampleChinese.

First decide whether the object itself exists and can be located reliably. If not, skip it. If it can be located and its precise name is clear, set confirmationStatus to "confirmed" and omit candidates. If it can be located but 2 or more similar names are genuinely plausible, keep the object, set confirmationStatus to "needsConfirmation", and return 2 or 3 candidates ordered most likely first. Each candidate must contain english, chinese, ipa, example, and exampleChinese. The top-level vocabulary fields must exactly match the first candidate. Do not invent weak alternatives. Never output "userConfirmed"; the app reserves it for a learner's choice.

${captionInstruction} The caption must be exactly one beginner-friendly sentence and no more than 24 words. Translate the caption into one natural, short simplified-Chinese sentence in captionChinese. Do not output markdown or commentary.`;
}

function masteredWordsInstruction(masteredWords: string[]): string {
  if (masteredWords.length === 0) return "";
  return `The learner already knows these English terms: ${JSON.stringify(masteredWords)}. When equally reliable useful objects are visible, prefer objects whose natural English names are not in this list. This is a preference, not a hard exclusion: include known objects if there are not enough reliable alternatives. Never invent, relabel, or choose an uncertain object merely to avoid a known term.`;
}

export function vocabularyPrompt(term: string): string {
  return `You are an English vocabulary learning assistant. Resolve the user's concrete object name and output JSON only.

The user entered: ${JSON.stringify(term)}

Return exactly this shape:
{
  "english": "window",
  "chinese": "窗户",
  "ipa": "/ˈwɪndoʊ/",
  "example": "The window is open.",
  "exampleChinese": "窗户是开着的。"
}

The input may be simplified Chinese or English. Treat the user's stated meaning as authoritative; do not inspect or reinterpret any image. Return a natural singular English noun or short noun phrase, simplified Chinese, standard IPA, one short beginner-friendly English example, and its natural simplified-Chinese translation in exampleChinese. Output no markdown or commentary.`;
}
