import { readingWords, type Project } from './project';

/**
 * 小红书正文的本地固定模板。
 * 它不是 AI 提示词，而是在 video-studio 返回发布文案时覆盖 AI 生成的小红书 body。
 * 当前使用方：video-studio；App 不使用这套平台发布模板。
 */
export function learningPost(p: Project) {
    return [
        p.sceneTheme ? `${p.sceneTheme}｜用一张照片学生活英语` : '用一张照片学生活英语',
        readingWords(p.words).map(w => `${w.english} ${w.ipa} ${w.chinese}`.trim()).join('\n'),
        `${p.caption}\n${p.captionChinese}`,
        p.interaction?.english ? `${p.interaction.english}\n${p.interaction.chinese}` : '你还会用哪些英语描述这个场景？',
    ].join('\n\n');
}
