import type {
  AnalyzeResult,
  VisionInput,
  VisionProvider,
  VocabularyDetails,
  VocabularyInput,
} from "../types.js";

export class MockVisionProvider implements VisionProvider {
  async analyze(input: VisionInput): Promise<AnalyzeResult> {
    return mockResult(input);
  }

  async analyzeStream(
    input: VisionInput,
    onObject: (object: AnalyzeResult["objects"][number]) => Promise<void> | void,
  ): Promise<AnalyzeResult> {
    const result = mockResult(input);
    for (const object of result.objects) {
      await abortableDelay(350, input.signal);
      await onObject(object);
    }
    return result;
  }

  async resolveVocabulary(input: VocabularyInput): Promise<VocabularyDetails> {
    const normalized = input.term.trim().toLowerCase();
    if (normalized === "窗户" || normalized === "window") {
      return { english: "window", chinese: "窗户", ipa: "/ˈwɪndoʊ/", example: "The window is open.", exampleChinese: "窗户是开着的。" };
    }
    return { english: input.term.trim(), chinese: input.term.trim(), ipa: "", example: `This is ${input.term.trim()}.`, exampleChinese: `这是${input.term.trim()}。` };
  }
}

function mockResult(input: VisionInput): AnalyzeResult {
  return {
    imageWidth: input.imageWidth,
    imageHeight: input.imageHeight,
    caption: input.captionStyle === "funny"
      ? "The mug is patiently waiting for its next coffee mission."
      : "A mug, a book, and a plant sit together on the table.",
    captionChinese: input.captionStyle === "funny"
      ? "这个杯子正耐心地等待下一次咖啡任务。"
      : "一个杯子、一本书和一盆植物摆在一起。",
    captionStyle: input.captionStyle,
    objects: [
      {
        id: "obj_01",
        english: "mug",
        chinese: "杯子",
        ipa: "/mʌɡ/",
        confidence: 0.96,
        box: { x: 0.58, y: 0.43, width: 0.22, height: 0.28 },
        anchor: { x: 0.69, y: 0.57 },
        example: "This is a mug.",
        exampleChinese: "这是一个杯子。",
        confirmationStatus: "needsConfirmation",
        candidates: [
          { english: "mug", chinese: "杯子", ipa: "/mʌɡ/", example: "This is a mug.", exampleChinese: "这是一个杯子。" },
          { english: "vase", chinese: "花瓶", ipa: "/veɪs/", example: "The vase has flowers.", exampleChinese: "花瓶里有花。" },
          { english: "jar", chinese: "罐子", ipa: "/dʒɑːr/", example: "The jar is empty.", exampleChinese: "罐子是空的。" },
        ],
      },
      {
        id: "obj_02",
        english: "book",
        chinese: "书",
        ipa: "/bʊk/",
        confidence: 0.93,
        box: { x: 0.12, y: 0.57, width: 0.30, height: 0.20 },
        anchor: { x: 0.27, y: 0.67 },
        example: "I am reading a book.",
        exampleChinese: "我正在读一本书。",
        confirmationStatus: "confirmed",
      },
      {
        id: "obj_03",
        english: "plant",
        chinese: "植物",
        ipa: "/plænt/",
        confidence: 0.91,
        box: { x: 0.08, y: 0.12, width: 0.22, height: 0.34 },
        anchor: { x: 0.19, y: 0.29 },
        example: "The plant is green.",
        exampleChinese: "这株植物是绿色的。",
        confirmationStatus: "confirmed",
      },
    ],
  };
}

function abortableDelay(milliseconds: number, signal?: AbortSignal): Promise<void> {
  if (signal?.aborted) return Promise.reject(signal.reason ?? new DOMException("Aborted", "AbortError"));
  return new Promise((resolve, reject) => {
    const handleAbort = () => {
      clearTimeout(timer);
      reject(signal?.reason ?? new DOMException("Aborted", "AbortError"));
    };
    const timer = setTimeout(() => {
      signal?.removeEventListener("abort", handleAbort);
      resolve();
    }, milliseconds);
    signal?.addEventListener("abort", handleAbort, { once: true });
  });
}
