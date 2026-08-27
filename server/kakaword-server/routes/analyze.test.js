import assert from "node:assert/strict";
import test from "node:test";
import { createApp } from "../app.js";
import { MockVisionProvider } from "../core/image-analysis/providers/mock.js";
const logger = {
    debug() { },
    info() { },
    warn() { },
    error() { },
};
const config = {
    port: 0,
    maxUploadBytes: 5 * 1024 * 1024,
    logLevel: "error",
    vision: { name: "mock", model: "mock" },
    usageLimits: {
        enabled: true,
        databaseURL: "postgres://unused",
        ipHashSecret: "test-secret-that-is-at-least-32-characters",
        perMinute: 10,
        dailyLimit: 500,
        dailyTimeZone: "Asia/Shanghai",
        trustProxy: true,
    },
};
test("streams validated mock objects before the complete result", async () => {
    const limiter = new FakeUsageLimiter();
    const app = makeApp(limiter);
    const response = await app.request("/v1/analyze", analyzeRequest());
    const body = await response.text();
    assert.equal(response.status, 200);
    assert.match(response.headers.get("content-type") ?? "", /^text\/event-stream/);
    const events = [...body.matchAll(/^event: (.+)$/gm)].map((match) => match[1]);
    assert.deepEqual(events, ["started", "object", "object", "object", "complete"]);
    assert.match(body, /"english":"mug"/);
    assert.match(body, /"captionStyle":"serious"/);
    assert.match(body, /"caption":"A mug, a book, and a plant sit together on the table\."/);
    assert.match(body, /"captionChinese":"一个杯子、一本书和一盆植物摆在一起。"/);
    assert.equal(limiter.minuteCalls, 1);
    assert.equal(limiter.dailyCalls, 1);
    assert.equal(limiter.lastClientIP, "203.0.113.10");
});
test("uses the requested caption style and resolves random to an actual style", async () => {
    const app = makeApp(new FakeUsageLimiter());
    const funnyResponse = await app.request("/v1/analyze", analyzeRequest("203.0.113.20", "funny"));
    const funnyBody = await funnyResponse.text();
    assert.match(funnyBody, /"captionStyle":"funny"/);
    assert.match(funnyBody, /coffee mission/);
    const randomResponse = await app.request("/v1/analyze", analyzeRequest("203.0.113.21", "random"));
    const randomBody = await randomResponse.text();
    assert.match(randomBody, /"captionStyle":"(?:serious|funny)"/);
    assert.doesNotMatch(randomBody, /"captionStyle":"random"/);
});
test("resolves Chinese or English vocabulary without an image", async () => {
    const limiter = new FakeUsageLimiter();
    const app = makeApp(limiter);
    const response = await app.request("/v1/vocabulary/resolve", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Forwarded-For": "203.0.113.22" },
        body: JSON.stringify({ term: "窗户" }),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
        english: "window",
        chinese: "窗户",
        ipa: "/ˈwɪndoʊ/",
        example: "The window is open.",
        exampleChinese: "窗户是开着的。",
    });
    assert.equal(limiter.minuteCalls, 1);
    assert.equal(limiter.dailyCalls, 1);
});
test("rejects invalid vocabulary before consuming the daily allowance", async () => {
    const limiter = new FakeUsageLimiter();
    const app = makeApp(limiter);
    const response = await app.request("/v1/vocabulary/resolve", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ term: "   " }),
    });
    assert.equal(response.status, 400);
    assert.equal(limiter.minuteCalls, 1);
    assert.equal(limiter.dailyCalls, 0);
});
test("applies minute and daily model-call limits to vocabulary requests", async () => {
    const minuteProvider = new CountingProvider();
    const minuteApp = makeApp(new FakeUsageLimiter({ allowed: false, retryAfterSeconds: 8 }), minuteProvider);
    const minuteResponse = await minuteApp.request("/v1/vocabulary/resolve", vocabularyRequest("window"));
    assert.equal(minuteResponse.status, 429);
    assert.equal(minuteProvider.calls, 0);
    const dailyProvider = new CountingProvider();
    const dailyApp = makeApp(new FakeUsageLimiter({ allowed: true, remaining: 9 }, { allowed: false, retryAfterSeconds: 60 }), dailyProvider);
    const dailyResponse = await dailyApp.request("/v1/vocabulary/resolve", vocabularyRequest("window"));
    assert.equal(dailyResponse.status, 429);
    assert.equal(dailyProvider.calls, 0);
});
test("returns a stable error when vocabulary generation fails", async () => {
    const app = makeApp(new FakeUsageLimiter(), new FailingVocabularyProvider());
    const response = await app.request("/v1/vocabulary/resolve", vocabularyRequest("window"));
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), {
        error: "VOCABULARY_FAILED",
        message: "单词信息生成失败，请稍后重试",
    });
});
test("rejects a minute-limited request before parsing the image or calling the provider", async () => {
    const limiter = new FakeUsageLimiter({ allowed: false, retryAfterSeconds: 6 });
    const provider = new CountingProvider();
    const app = makeApp(limiter, provider);
    const response = await app.request("/v1/analyze", {
        method: "POST",
        headers: { "X-Forwarded-For": "203.0.113.11" },
        body: new FormData(),
    });
    assert.equal(response.status, 429);
    assert.equal(response.headers.get("retry-after"), "6");
    assert.deepEqual(await response.json(), {
        error: "RATE_LIMITED",
        message: "识别有点频繁，请在 6 秒后再试",
        retryAfterSeconds: 6,
    });
    assert.equal(limiter.dailyCalls, 0);
    assert.equal(provider.calls, 0);
});
test("invalid images consume the minute allowance but not the daily model allowance", async () => {
    const limiter = new FakeUsageLimiter();
    const provider = new CountingProvider();
    const app = makeApp(limiter, provider);
    const form = new FormData();
    form.append("image", new File(["not an image"], "bad.png", { type: "image/png" }));
    const response = await app.request("/v1/analyze", {
        method: "POST",
        headers: { "X-Forwarded-For": "203.0.113.12" },
        body: form,
    });
    assert.equal(response.status, 400);
    assert.equal(limiter.minuteCalls, 1);
    assert.equal(limiter.dailyCalls, 0);
    assert.equal(provider.calls, 0);
});
test("rejects a valid image after the global daily allowance is exhausted", async () => {
    const limiter = new FakeUsageLimiter({ allowed: true, remaining: 9 }, { allowed: false, retryAfterSeconds: 3_600 });
    const provider = new CountingProvider();
    const app = makeApp(limiter, provider);
    const response = await app.request("/v1/analyze", analyzeRequest("203.0.113.13"));
    assert.equal(response.status, 429);
    assert.equal(response.headers.get("retry-after"), "3600");
    assert.deepEqual(await response.json(), {
        error: "DAILY_LIMIT_REACHED",
        message: "今天的识别额度已用完，请明天再试",
        retryAfterSeconds: 3_600,
    });
    assert.equal(provider.calls, 0);
});
test("fails closed when the usage database is unavailable", async () => {
    const limiter = new FakeUsageLimiter();
    limiter.minuteError = new Error("database unavailable");
    const provider = new CountingProvider();
    const app = makeApp(limiter, provider);
    const response = await app.request("/v1/analyze", analyzeRequest("203.0.113.14"));
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), {
        error: "USAGE_LIMIT_UNAVAILABLE",
        message: "识别服务暂时不可用，请稍后重试",
    });
    assert.equal(provider.calls, 0);
});
test("fails closed when the daily counter cannot be updated", async () => {
    const limiter = new FakeUsageLimiter();
    limiter.dailyError = new Error("database unavailable");
    const provider = new CountingProvider();
    const app = makeApp(limiter, provider);
    const response = await app.request("/v1/analyze", analyzeRequest("203.0.113.16"));
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), {
        error: "USAGE_LIMIT_UNAVAILABLE",
        message: "识别服务暂时不可用，请稍后重试",
    });
    assert.equal(limiter.minuteCalls, 1);
    assert.equal(limiter.dailyCalls, 1);
    assert.equal(provider.calls, 0);
});
test("aborts the provider when the client cancels the SSE response", async () => {
    let acknowledgeAbort;
    const providerAborted = new Promise((resolve) => { acknowledgeAbort = resolve; });
    const provider = new AbortAwareProvider(() => acknowledgeAbort?.());
    const app = makeApp(new FakeUsageLimiter(), provider);
    const response = await app.request("/v1/analyze", analyzeRequest("203.0.113.15"));
    assert.equal(response.status, 200);
    const reader = response.body?.getReader();
    assert.ok(reader);
    await reader.read();
    await reader.cancel();
    await Promise.race([
        providerAborted,
        new Promise((_, reject) => setTimeout(() => reject(new Error("provider was not aborted")), 1_000)),
    ]);
});
function makeApp(usageLimiter, provider = new MockVisionProvider()) {
    return createApp({ config, provider, usageLimiter, logger });
}
function analyzeRequest(ip = "203.0.113.10", captionStyle) {
    const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "base64");
    const form = new FormData();
    form.append("maxObjects", "3");
    if (captionStyle)
        form.append("captionStyle", captionStyle);
    form.append("image", new File([png], "test.png", { type: "image/png" }));
    return { method: "POST", headers: { "X-Forwarded-For": ip }, body: form };
}
function vocabularyRequest(term) {
    return {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Forwarded-For": "203.0.113.30" },
        body: JSON.stringify({ term }),
    };
}
class FakeUsageLimiter {
    minuteDecision;
    dailyDecision;
    minuteCalls = 0;
    dailyCalls = 0;
    lastClientIP;
    minuteError;
    dailyError;
    constructor(minuteDecision = { allowed: true, remaining: 9 }, dailyDecision = { allowed: true, remaining: 499 }) {
        this.minuteDecision = minuteDecision;
        this.dailyDecision = dailyDecision;
    }
    async consumeMinute(clientIP) {
        this.minuteCalls += 1;
        this.lastClientIP = clientIP;
        if (this.minuteError)
            throw this.minuteError;
        return this.minuteDecision;
    }
    async consumeDaily() {
        this.dailyCalls += 1;
        if (this.dailyError)
            throw this.dailyError;
        return this.dailyDecision;
    }
    async close() { }
}
class CountingProvider {
    calls = 0;
    async analyze(input) {
        this.calls += 1;
        return {
            imageWidth: input.imageWidth,
            imageHeight: input.imageHeight,
            objects: [],
            caption: "There are no learning objects in this image.",
            captionChinese: "这张图片中没有适合学习的物体。",
            captionStyle: input.captionStyle,
        };
    }
    async resolveVocabulary(input) {
        this.calls += 1;
        return { english: input.term, chinese: input.term, ipa: "", example: `This is ${input.term}.` };
    }
}
class AbortAwareProvider {
    onAbort;
    constructor(onAbort) {
        this.onAbort = onAbort;
    }
    async analyze(input) {
        return this.waitForAbort(input);
    }
    async analyzeStream(input) {
        return this.waitForAbort(input);
    }
    async resolveVocabulary() {
        throw new Error("not used");
    }
    async waitForAbort(input) {
        return new Promise((_, reject) => {
            const handleAbort = () => {
                this.onAbort();
                reject(input.signal?.reason ?? new DOMException("Aborted", "AbortError"));
            };
            if (input.signal?.aborted)
                handleAbort();
            else
                input.signal?.addEventListener("abort", handleAbort, { once: true });
        });
    }
}
class FailingVocabularyProvider extends MockVisionProvider {
    async resolveVocabulary() {
        throw new Error("provider unavailable");
    }
}
