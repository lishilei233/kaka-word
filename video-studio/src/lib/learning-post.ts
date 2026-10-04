import { descriptionSentences, readingWords, type Project, type SocialCopy } from './project';

export const PUBLISHING_SCENE_LIMIT = 29;
export const publishingHashtags = ['生活英语', '英语单词', '看图学英语', '英语学习'] as const;

export function publishingScene(p: Project) {
    return (p.publishingScene ?? p.sceneTheme ?? '').trim();
}

export function publishingSceneIssues(p: Project) {
    const scene = publishingScene(p);
    if (!scene) return ['请填写场景名。'];
    if (scene.length > PUBLISHING_SCENE_LIMIT) return ['场景名最多 29 字，请缩短。'];
    return [];
}

export function fixedCoverTitle(p: Project) {
    const scene = publishingScene(p);
    return scene ? `${scene}，这${readingWords(p.words, p.caption).length}个英语你会吗？` : '';
}

export function publishingIssues(p: Project) {
    const issues = publishingSceneIssues(p);
    if (!p.words.length || p.words.some(word => !word.english.trim())) issues.push('请完善英文词表。');
    if (descriptionSentences(p).some(sentence => !sentence.english.trim() || !sentence.chinese.trim())) issues.push('请完善每组照片描述的英文和中文。');
    if (p.interaction?.enabled && (!p.interaction.english.trim() || !p.interaction.chinese.trim())) issues.push('请完善互动句的英文和中文。');
    return issues;
}

/** Shared fixed body; hashtags are appended only by the clipboard formatter. */
export function learningPost(p: Project) {
    return [
        '把每天看到的东西，变成英语。📷',
        `今天看看「${publishingScene(p)}」里有哪些英文单词：\n${readingWords(p.words, p.caption).map(word => word.english.trim()).join(' / ')}`,
        `再学一句：\n${descriptionSentences(p).map(sentence => `${sentence.english.trim()}\n${sentence.chinese.trim()}`).join('\n')}`,
        ...(p.interaction?.enabled ? [`${p.interaction.english.trim()}\n${p.interaction.chinese.trim()}`] : []),
        '照片里还有什么，你会用英语说吗？👀',
    ].join('\n\n');
}

export function publishingPost(p: Project): SocialCopy['xiaohongshu'] {
    return { title: `看照片学单词｜${publishingScene(p)}`, body: learningPost(p), hashtags: [...publishingHashtags] };
}

export function fixedSocialCopy(p: Project): SocialCopy {
    return { xiaohongshu: publishingPost(p), douyin: publishingPost(p), channels: publishingPost(p) };
}

export function publishingText(p: Project, part: 'title' | 'body' | 'all') {
    const post = publishingPost(p);
    if (part === 'title') return post.title;
    const body = `${post.body}\n\n${post.hashtags.map(tag => `#${tag}`).join(' ')}`;
    return part === 'body' ? body : `${post.title}\n\n${body}`;
}
