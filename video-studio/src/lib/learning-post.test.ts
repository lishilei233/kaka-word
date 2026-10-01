import { test } from 'node:test';
import assert from 'node:assert/strict';
import { emptyProject, projectSchema, type Project } from './project';
import { fixedCoverTitle, fixedSocialCopy, publishingIssues, publishingPost, publishingScene, publishingText } from './learning-post';

const p: Project = { ...emptyProject, sceneTheme: '书架一角',
    words: [
        { id: 'state', english: 'open', chinese: '打开的', ipa: '/oʊpən/', kind: 'state' },
        { id: 'book', english: 'book', chinese: '书', ipa: '/bʊk/', kind: 'object', needsLocation: true },
        { id: 'shelf', english: 'bookshelf', chinese: '书架', ipa: '', kind: 'object', needsLocation: true },
    ], caption: 'Books sit on a shelf.', captionChinese: '书摆在书架上。',
    captionSentences: [{ english: 'Books sit on a shelf.', chinese: '书摆在书架上。' }, { english: 'A book is open.', chinese: '一本书打开着。' }],
};
test('three platforms use the exact same fixed template and plain-text formatting', () => {
    const expectedBody = '把每天看到的东西，变成英语。📷\n\n今天看看「书架一角」里有哪些英文单词：\nbook / bookshelf / open\n\n再学一句：\nBooks sit on a shelf.\n书摆在书架上。\nA book is open.\n一本书打开着。\n\n照片里还有什么，你会用英语说吗？👀';
    const copy = fixedSocialCopy(p);
    assert.deepEqual(copy.xiaohongshu, copy.douyin);
    assert.deepEqual(copy.douyin, copy.channels);
    assert.equal(copy.xiaohongshu.title, '看照片学单词｜书架一角');
    assert.equal(copy.xiaohongshu.body, expectedBody);
    const tags = '#生活英语 #英语单词 #看图学英语 #英语学习';
    assert.equal(publishingText(p, 'body'), `${expectedBody}\n\n${tags}`);
    assert.equal(publishingText(p, 'all'), `看照片学单词｜书架一角\n\n${expectedBody}\n\n${tags}`);
    assert.equal(publishingText(p, 'title'), copy.xiaohongshu.title);
    assert.equal(fixedCoverTitle(p), '书架一角，你会几个单词？');
});
test('manual scene survives round trip without altering video data or historical copy', () => {
    const saved = projectSchema.parse({ ...p, publishingScene: '窗边书架', socialCopy: fixedSocialCopy(p), cover: { template: 'scene-question', title: '旧标题', audienceTitles: { adult: '旧受众标题' }, scale: .9, words: {} } });
    const restored = projectSchema.parse(JSON.parse(JSON.stringify(saved)));
    assert.equal(publishingScene(restored), '窗边书架');
    assert.equal(restored.sceneTheme, '书架一角');
    assert.equal(restored.cover?.title, '旧标题');
    assert.equal(restored.socialCopy?.xiaohongshu.title, '看照片学单词｜书架一角');
    assert.equal(publishingPost(restored).title, '看照片学单词｜窗边书架');
    assert.equal(restored.version, 4);
    assert.deepEqual(restored.words, p.words);
    assert.deepEqual(restored.captionSentences, p.captionSentences);
});
test('legacy captions stay a single paired block and changes are reflected immediately', () => {
    const legacy = { ...p, captionSentences: undefined, caption: 'One. Two.', captionChinese: '一句。两句。' };
    assert.ok(publishingPost(legacy).body.includes('再学一句：\nOne. Two.\n一句。两句。'));
    const changed = { ...legacy, publishingScene: '桌面', words: p.words.slice(0, 1), caption: 'It is open.', captionChinese: '它打开着。' };
    assert.equal(fixedCoverTitle(changed), '桌面，你会几个单词？');
    assert.ok(publishingPost(changed).body.includes('：\nopen\n\n再学一句：\nIt is open.\n它打开着。'));
});
test('enabled interaction is included after the descriptions and remains out when disabled', () => {
    const interaction = { enabled: true, english: 'What else can you see?', chinese: '你还看到了什么？' };
    const enabled = { ...p, interaction };
    assert.ok(publishingText(enabled, 'body').includes('一本书打开着。\n\nWhat else can you see?\n你还看到了什么？\n\n照片里还有什么'));
    assert.deepEqual(fixedSocialCopy(enabled).xiaohongshu, fixedSocialCopy(enabled).douyin);
    assert.ok(!publishingText({ ...enabled, interaction: { ...interaction, enabled: false } }, 'body').includes(interaction.english));
    assert.ok(publishingIssues({ ...enabled, interaction: { ...interaction, chinese: ' ' } }).includes('请完善互动句的英文和中文。'));
});
test('missing scene, vocabulary or paired description blocks every copy action', () => {
    assert.deepEqual(publishingIssues(p), []);
    for (const patch of [{ publishingScene: '' }, { sceneTheme: undefined }, { publishingScene: '长'.repeat(30) }, { words: [] }, { words: [{ ...p.words[0], english: ' ' }] }, { captionSentences: [{ english: 'A book.', chinese: '' }] }, { captionSentences: undefined, caption: '' }]) {
        assert.ok(publishingIssues({ ...p, ...patch }).length > 0);
    }
    assert.equal(publishingScene({ ...p, publishingScene: '' }), '');
    assert.equal(projectSchema.safeParse({ ...p, publishingScene: '长'.repeat(30) }).success, false);
    assert.equal(projectSchema.safeParse({ ...p, publishingScene: '长'.repeat(29) }).success, true);
});
