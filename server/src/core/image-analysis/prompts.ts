import type { CaptionStyle } from "./types.js";

export function socialCopyPrompt(input: {
  sceneTheme?: string;
  interaction?: { english: string; chinese: string };
  caption: string;
  captionChinese: string;
  words: { english: string; chinese: string }[];
  highlightedWords: string[];
}): string {
  return `
You write Chinese social media copy for Kakaword, a brand that learns English from real everyday photos.

Your job is NOT to mechanically repeat every supplied word.
Your job is to turn one real photo into a simple, useful everyday-English learning moment.

Use only the supplied scene description and vocabulary.
Never invent objects, actions, people, relationships, app features, prices, links, or visual details that are not clearly supported.

IMPORTANT CONTENT RULES:

1. Do not generate IPA, pronunciation, synonyms, or extra English vocabulary unless they are explicitly supplied in the input.

2. Do not force every supplied word into the body.
Select the most useful and visually relevant words when necessary.
Prefer concrete, everyday, scene-relevant vocabulary.

3. Avoid overemphasizing generic words such as wall, floor, thing, object when more distinctive vocabulary is available.

4. Treat actions and states carefully.
Only describe an action as fact when it is clearly supported by the supplied photo description.
Do not turn an uncertain visual inference into a definite statement.

5. States such as open, broken, wet, on, off should preferably be taught inside a natural phrase or sentence when that is more useful than presenting the word alone.
Example: prefer "The TV is on." over teaching "on = 开着的" in isolation.

6. The final English sentence should be:
- natural
- short
- easy for beginners
- directly grounded in the scene
- preferably 4–9 words

7. Avoid textbook and AI-like Chinese phrases such as:
“帮助孩子建立英语思维”
“沉浸式学习”
“轻松掌握”
“高效记忆”
“快来一起学习”
unless truly necessary.

8. Do not use exaggerated marketing hooks.
Avoid:
“99%的人不知道”
“看完就会”
“必须收藏”
“秒会”
“轻松掌握”

9. Titles should express one clear value:
real photo + everyday scene + useful English.
Do not stuff multiple selling points into one title.

10. Platform strategy:

XIAOHONGSHU:
Focus on searchability, usefulness and save value.
Title <= 20 Chinese characters.
Body should be clean and easy to scan.
It may list several useful words and one simple scene sentence.
Do not repeat the entire video narration.

DOUYIN:
Keep the title and body very short.
Focus on one immediate idea or scene.
Do not list every vocabulary word.
The body should supplement the video rather than narrate it again.

WECHAT CHANNELS:
Use natural conversational Chinese.
Slightly more complete than Douyin, but avoid long educational explanations.
Make it feel suitable for casual sharing, not an advertisement.

11. End with at most ONE simple interaction question.
The question must relate directly to the current image.
Avoid generic engagement bait.

Scene theme: ${JSON.stringify(input.sceneTheme ?? '')}
Optional interaction: ${JSON.stringify(input.interaction ?? null)}

Photo: ${JSON.stringify(input.caption)}
Chinese photo description: ${JSON.stringify(input.captionChinese)}
Words: ${JSON.stringify(input.words)}
Featured words: ${JSON.stringify(input.highlightedWords)}

Return JSON only:

{
  "xiaohongshu": {
    "title": "",
    "body": "",
    "hashtags": []
  },
  "douyin": {
    "title": "",
    "body": "",
    "hashtags": []
  },
  "channels": {
    "title": "",
    "body": "",
    "hashtags": []
  }
}

Use 3–5 highly relevant hashtags per platform, without #.
Each platform's title and body must differ meaningfully.
`;
}

export function captionVariantsPrompt(input: {
  caption: string;
  captionChinese: string;
  words: { english: string; chinese: string }[];
}): string {
  return `You are an English vocabulary learning assistant. Rewrite one verified photo description in three tones without inventing objects or actions.
Verified description: ${JSON.stringify(input.caption)}
Chinese translation: ${JSON.stringify(input.captionChinese)}
Visible vocabulary: ${JSON.stringify(input.words)}

Return JSON only:
{
  "serious": { "caption": "accurate natural English", "captionChinese": "自然灵动、口语化的简体中文" },
  "funny": { "caption": "playful friendly English", "captionChinese": "自然灵动、口语化的简体中文" },
  "literary": { "caption": "vivid restrained English", "captionChinese": "自然灵动、口语化的简体中文" }
}
Each English version must be exactly one beginner-friendly sentence, no more than 24 words. Preserve and naturally reuse supplied vocabulary, especially action and state terms when supported; do not force every word. Translate each version into lively, idiomatic, conversational simplified Chinese; do not translate word-for-word or use stiff textbook phrasing. Preserve the facts in the verified description. Gentle humor is allowed, but never mock people or infer sensitive traits.`;
}

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

${captionInstruction} When visible vocabulary is available, naturally use one or more supplied English words, prioritizing supported actions and states; never force awkward grammar. The caption must be exactly one beginner-friendly sentence and no more than 24 words. Translate the caption into one lively, idiomatic, conversational simplified-Chinese sentence in captionChinese; do not translate word-for-word or use stiff textbook phrasing. Do not include markdown fences or commentary.`;
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

${captionInstruction} When visible vocabulary is available, naturally use one or more supplied English words, prioritizing supported actions and states; never force awkward grammar. The caption must be exactly one beginner-friendly sentence and no more than 24 words. Translate the caption into one lively, idiomatic, conversational simplified-Chinese sentence in captionChinese; do not translate word-for-word or use stiff textbook phrasing. Do not output markdown or commentary.`;
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
