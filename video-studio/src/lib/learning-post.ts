import { readingWords, type Project } from './project';

export function learningPost(p: Project) {
    return [
        p.sceneTheme ? `${p.sceneTheme}｜用一张照片学生活英语` : '用一张照片学生活英语',
        readingWords(p.words).map(w => `${w.english} ${w.ipa} ${w.chinese}`.trim()).join('\n'),
        `${p.caption}\n${p.captionChinese}`,
        p.interaction?.english ? `${p.interaction.english}\n${p.interaction.chinese}` : '你还会用哪些英语描述这个场景？',
    ].join('\n\n');
}
