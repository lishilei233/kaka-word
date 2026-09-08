import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";
import { createApp } from "../app.js";
import type { ServerConfig } from "../config.js";
import { DisabledAccessService } from "../core/access/index.js";
import type {
  AccessPrincipal,
  RecognitionFeedbackInput,
} from "../core/access/types.js";
import { MockVisionProvider } from "../core/image-analysis/providers/mock.js";
import type { AnalyzeUsageLimiter } from "../core/usage-limits/index.js";
import type { Logger } from "../utils/logger.js";

const logs: Array<{ event: string; fields: Record<string, unknown> }> = [];
const logger: Logger = {
  debug() {},
  info(event, fields) { logs.push({ event, fields: fields ?? {} }); },
  warn(event, fields) { logs.push({ event, fields: fields ?? {} }); },
  error(event, fields) { logs.push({ event, fields: fields ?? {} }); },
};

test("records authenticated recognition feedback without exposing a request ID", async () => {
  logs.length = 0;
  const service = new RecordingAccessService();
  const response = await appFor(service).request("/v1/recognition-feedback", {
    method: "POST",
    headers: {
      authorization: "Bearer test-access-token",
      "content-type": "application/json",
      "x-request-id": "should-not-be-logged",
    },
    body: JSON.stringify({
      original: { english: " Mug ", chinese: " 杯子 " },
      selected: { english: "VASE", chinese: " 花瓶 " },
      selection: "second",
    }),
  });

  assert.equal(response.status, 204);
  assert.equal(response.headers.get("x-request-id"), null);
  assert.deepEqual(service.inputs, [{
    original: { english: "Mug", chinese: "杯子" },
    selected: { english: "VASE", chinese: "花瓶" },
    selection: "second",
  }]);
  assert.equal(logs.some(({ fields }) => "requestId" in fields), false);
  assert.equal(logs.some(({ fields }) => JSON.stringify(fields).includes("should-not-be-logged")), false);
});

test("rejects unauthenticated and malformed recognition feedback", async () => {
  const service = new RecordingAccessService();
  const unauthenticated = await appFor(service).request("/v1/recognition-feedback", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(validPayload()),
  });
  assert.equal(unauthenticated.status, 401);

  const malformed = await appFor(service).request("/v1/recognition-feedback", {
    method: "POST",
    headers: {
      authorization: "Bearer test-access-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({ ...validPayload(), selection: "fourth" }),
  });
  assert.equal(malformed.status, 400);
  assert.equal(service.inputs.length, 0);
});

function validPayload() {
  return {
    original: { english: "mug", chinese: "杯子" },
    selected: { english: "mug", chinese: "杯子" },
    selection: "first",
  };
}

function appFor(accessService: RecordingAccessService) {
  const config: ServerConfig = {
    port: 0,
    maxUploadBytes: 5 * 1024 * 1024,
    logLevel: "error",
    vision: { name: "mock", model: "mock" },
    usageLimits: {
      enabled: false,
      databaseURL: "",
      ipHashSecret: "",
      perMinute: 10,
      dailyLimit: 500,
      dailyTimeZone: "Asia/Shanghai",
      trustProxy: false,
    },
    access: {
      enabled: false,
      databaseURL: "",
      tokenHashSecret: "",
      tokenTTLSeconds: 3_600,
      bundleId: "com.kakaword.app",
      appleRootCertificatePaths: [],
      appleOnlineChecks: false,
      monthlyProductId: "com.kakaword.app.membership.month",
      annualProductId: "com.kakaword.app.membership.annual",
      deviceCheck: { keyId: "", teamId: "", privateKey: "", environment: "development" },
    },
  };
  return createApp({
    config,
    provider: new MockVisionProvider(),
    usageLimiter: new NeverCalledLimiter(),
    accessService,
    logger,
  });
}

class RecordingAccessService extends DisabledAccessService {
  readonly inputs: RecognitionFeedbackInput[] = [];

  override async authenticate(rawToken: string | undefined): Promise<AccessPrincipal | null> {
    if (rawToken !== "Bearer test-access-token") return null;
    return {
      accessTokenHash: "test",
      installationId: randomUUID(),
      subscriptionEnvironment: null,
      originalTransactionId: null,
    };
  }

  override async recordRecognitionFeedback(input: RecognitionFeedbackInput): Promise<void> {
    this.inputs.push(input);
  }
}

class NeverCalledLimiter implements AnalyzeUsageLimiter {
  async consumeMinute(): Promise<never> { throw new Error("not used"); }
  async consumeDaily(): Promise<never> { throw new Error("not used"); }
  async close(): Promise<void> {}
}
