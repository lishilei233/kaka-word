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

const updatedAt = "2026-08-26T00:00:00+08:00";

export const contentDocuments: Record<ContentKey, ContentDocument> = {
  privacy: {
    key: "privacy",
    locale: "zh-CN",
    title: "隐私政策",
    code: "PRIVACY",
    version: "1.1.0",
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
        heading: "匿名设备与会员信息",
        paragraphs: [
          "为了发放每台设备终身 3 次的免费识别额度，应用会生成随机安装标识，并使用 Apple DeviceCheck 保存已使用免费次数的设备状态。为了验证订阅并在同一 Apple 购买身份的设备间共享会员额度，我们会处理 Apple 提供的产品标识、原始交易标识、订阅状态和有效期。",
          "访问令牌只以不可逆摘要形式保存在服务器。我们不会取得你的 Apple ID、付款卡号或 App Store 密码，也不会使用这些匿名标识建立广告画像。",
        ],
        bullets: [
          "额度记录：方案、已用与预占次数、额度周期和操作标识。",
          "订阅记录：产品、原始交易标识、续订、宽限期、到期、退款或撤销状态。",
          "服务指标：不包含照片和个人身份的聚合使用与购买结果。",
        ],
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
    version: "1.1.0",
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
        heading: "免费额度与会员",
        paragraphs: [
          "每台设备可获得终身 3 次完整 AI 拍照识别。月会员与年会员在每个订阅月获得 100 次识别额度，额度不结转。只有成功生成至少一个有效物体的识别才扣除 1 次；失败、空结果、取消或超时不扣除。每次成功的重新识别也会扣除 1 次。",
          "会员可以使用 AI 单词纠错，纠错不会扣除拍照识别额度，但仍受安全与服务容量限制。免费额度与会员识别的输出质量一致；额度用尽或会员到期后，已有历史、发音、分享和亲子寻宝仍可使用。",
        ],
        bullets: [],
      },
      {
        heading: "自动续订、取消与退款",
        paragraphs: [
          "月会员和年会员是通过 App Store 提供的自动续订订阅。确认购买后由 Apple 从你的账户扣款；除非在当前订阅期结束前至少 24 小时关闭自动续订，否则订阅会按 App Store 显示的完整金额续订。你可以在 App Store 的订阅管理中取消，取消后权益保留至当前付费期结束。",
          "符合条件的账单问题可进入最多 16 天的宽限期，宽限期内会员权益照常。退款、撤销或宽限期结束后，会员权益会立即停止。退款申请和结果由 Apple 按其规则处理。",
        ],
        bullets: [
          "不提供免费试用、家庭共享、次数包或无限识别。",
          "关闭自动续订、升级或降级不会提前赠送新的月度额度。",
          "最终价格、扣款币种和税费以购买确认界面显示的信息为准。",
        ],
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
