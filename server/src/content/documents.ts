export type ContentKey = "privacy" | "terms" | "about";

export type ContentSection = {
  heading: string;
  paragraphs: string[];
  bullets: string[];
};

export type ContentDocument = {
  key: ContentKey;
  locale: "zh-CN";
  title: string;
  code: string;
  version: string;
  updatedAt: string;
  summary: string;
  sections: ContentSection[];
};

const updatedAt = "2026-08-24T00:00:00+08:00";

export const contentDocuments: Record<ContentKey, ContentDocument> = {
  privacy: {
    key: "privacy",
    locale: "zh-CN",
    title: "隐私政策",
    code: "PRIVACY",
    version: "1.0.0",
    updatedAt,
    summary: "我们尽量让咔咔单词只处理完成识别所必需的信息。",
    sections: [
      {
        heading: "照片与识别",
        paragraphs: [
          "咔咔单词会将你主动拍摄或选择的照片发送给 AI 服务进行即时识别。照片不会写入咔咔单词应用服务器、对象存储或业务数据库。",
          "识别完成后，照片、任务进度与贴纸仅保存在当前设备。",
        ],
        bullets: [],
      },
      {
        heading: "设备端处理",
        paragraphs: [
          "生成分享卡时，应用会把照片和学习内容重新绘制为新的图片，因此不会继承原照片的拍摄位置和时间元数据。应用不会自动识别或模糊人脸，分享前请自行确认画面内容。",
        ],
        bullets: [],
      },
      {
        heading: "你可以控制的数据",
        paragraphs: ["你可以在设置中清空当前设备上的全部历史记录。清空后，照片和本地识别结果无法恢复。"],
        bullets: [],
      },
    ],
  },
  terms: {
    key: "terms",
    locale: "zh-CN",
    title: "服务条款",
    code: "TERMS",
    version: "1.0.0",
    updatedAt,
    summary: "使用咔咔单词，即表示你同意在合理、合法的范围内使用本服务。",
    sections: [
      {
        heading: "服务内容",
        paragraphs: [
          "咔咔单词提供基于 AI 的图片识别与语言学习辅助。服务可能因网络、模型或其他技术原因暂时不可用。",
        ],
        bullets: [],
      },
      {
        heading: "识别结果",
        paragraphs: [
          "AI 返回的物体名称、位置、音标和例句可能存在错误，仅供学习参考。你应当根据实际情况判断和使用识别结果。",
        ],
        bullets: [],
      },
      {
        heading: "使用要求",
        paragraphs: ["请只上传你有权处理的照片，并遵守适用的法律法规。"],
        bullets: [
          "不要上传包含敏感个人信息且未经授权的照片。",
          "不要上传违法、侵权或你无权处理的内容。",
          "不要尝试干扰、滥用或绕过服务的访问限制。",
        ],
      },
    ],
  },
  about: {
    key: "about",
    locale: "zh-CN",
    title: "关于",
    code: "ABOUT",
    version: "1.0.0",
    updatedAt,
    summary: "看见，\n就会说。",
    sections: [
      {
        heading: "KAKAWORD",
        paragraphs: ["咔咔单词用 AI 找到照片中值得学习的物体，把英文单词贴回真实世界。"],
        bullets: [],
      },
    ],
  },
};

export function isContentKey(value: string): value is ContentKey {
  return value === "privacy" || value === "terms" || value === "about";
}
