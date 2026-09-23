/** Safe diagnostics only: never include model text, prompts, or images in errors. */
export class QwenResponseError extends Error {
  constructor(readonly reason: string, details: Record<string, unknown>) {
    const safe = Object.fromEntries(Object.entries(details).filter(([, value]) => value !== undefined));
    super(`Qwen ${reason}: ${JSON.stringify(safe)}`);
    this.name = "QwenResponseError";
  }
}

function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function identifier(value: unknown): string | undefined {
  return typeof value === "string" && /^[A-Za-z0-9_.:/-]{1,160}$/.test(value) ? value : undefined;
}

export class QwenResponseReader {
  content = "";
  private chunks = 0;
  private finishReason: string | undefined;
  private requestID: string | undefined;
  private completionTokens: number | undefined;

  constructor(private readonly contentType: string | null, requestID: string | null) {
    this.requestID = identifier(requestID);
  }

  private fail(reason: string, extra: Record<string, unknown> = {}): never {
    throw new QwenResponseError(reason, {
      contentType: this.contentType?.split(";")[0].slice(0, 80),
      upstreamRequestId: this.requestID, chunks: this.chunks, contentLength: this.content.length,
      finishReason: this.finishReason, completionTokens: this.completionTokens, ...extra,
    });
  }

  push(raw: string, streaming: boolean): string {
    let parsed: unknown;
    try { parsed = JSON.parse(raw); } catch { return this.fail("returned an invalid response envelope"); }
    const payload = record(parsed);
    this.chunks++;
    this.requestID = identifier(payload.request_id) ?? identifier(payload.id) ?? this.requestID;
    const error = record(payload.error);
    if (payload.error || payload.code) {
      throw new QwenResponseError("returned an upstream error", {
        upstreamRequestId: this.requestID, code: identifier(error.code) ?? identifier(payload.code),
        type: identifier(error.type),
      });
    }
    const tokens = record(payload.usage).completion_tokens;
    if (typeof tokens === "number" && Number.isFinite(tokens)) this.completionTokens = tokens;
    const choices = Array.isArray(payload.choices) ? payload.choices : [];
    // A usage-only chunk is valid, but an unknown envelope must not disappear silently.
    if (!choices.length) {
      if (payload.usage) return "";
      return this.fail("returned no choices");
    }
    const choice = record(choices[0]);
    const reason = identifier(choice.finish_reason);
    if (reason) this.finishReason = reason;
    const message = record(streaming ? choice.delta : choice.message);
    if (message.refusal) return this.fail("refused the request");
    const fragment = message.content;
    if (fragment !== null && fragment !== undefined && typeof fragment !== "string") return this.fail("returned an unsupported content format");
    const text = typeof fragment === "string" ? fragment : "";
    this.content += text;
    if (reason && reason !== "stop") return this.fail(reason === "length" ? "output was truncated" : "ended without a normal completion");
    return text;
  }

  json(): unknown {
    if (!this.content.trim()) return this.fail("returned empty content");
    let value: unknown;
    try { value = JSON.parse(this.content); } catch { return this.fail("returned invalid or incomplete JSON content"); }
    if (value === null || typeof value !== "object" || Array.isArray(value)) return this.fail("returned a non-object JSON value", { jsonType: value === null ? "null" : Array.isArray(value) ? "array" : typeof value });
    return value;
  }
}
