import { randomUUID, sign } from "node:crypto";
import type { DeviceCheckConfig } from "../../config.js";
import type { DeviceChecking } from "./types.js";

type DeviceCheckQueryResponse = {
  bit0?: boolean;
  bit1?: boolean;
};

export class AppleDeviceCheckClient implements DeviceChecking {
  private cachedAuthorization?: { value: string; expiresAt: number };

  constructor(private readonly config: DeviceCheckConfig) {}

  async queryBits(deviceToken: string): Promise<number> {
    const payload = await this.request<DeviceCheckQueryResponse>("query_two_bits", deviceToken);
    return (payload.bit0 ? 1 : 0) + (payload.bit1 ? 2 : 0);
  }

  async updateBits(deviceToken: string, usedCount: number): Promise<void> {
    const normalized = Math.min(Math.max(Math.trunc(usedCount), 0), 3);
    await this.request("update_two_bits", deviceToken, {
      bit0: (normalized & 1) !== 0,
      bit1: (normalized & 2) !== 0,
    });
  }

  private async request<T = unknown>(
    action: "query_two_bits" | "update_two_bits",
    deviceToken: string,
    extra: Record<string, unknown> = {},
  ): Promise<T> {
    const host = this.config.environment === "development"
      ? "https://api.development.devicecheck.apple.com"
      : "https://api.devicecheck.apple.com";
    const response = await fetch(`${host}/v1/${action}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.authorizationToken()}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        device_token: deviceToken,
        transaction_id: randomUUID(),
        timestamp: Date.now(),
        ...extra,
      }),
      signal: AbortSignal.timeout(10_000),
    });
    const body = await response.text().catch(() => "");
    if (!response.ok) {
      throw new Error(`DeviceCheck ${action} failed (${response.status}): ${body.slice(0, 256)}`);
    }
    if (action === "update_two_bits") return undefined as T;
    // Apple returns HTTP 200 with this plain-text response for a device whose
    // two-bit state has never been initialized. Treat it as both bits false;
    // the first successful quota commit will initialize the state via update.
    if (action === "query_two_bits" && body.trim() === "Failed to find bit state") {
      return {} as T;
    }
    try {
      return JSON.parse(body) as T;
    } catch {
      const contentType = response.headers.get("content-type") ?? "unknown content type";
      throw new Error(
        `DeviceCheck ${action} returned invalid JSON (${response.status}, ${contentType}): ${body.slice(0, 256)}`,
      );
    }
  }

  private authorizationToken(): string {
    const now = Math.floor(Date.now() / 1_000);
    if (this.cachedAuthorization && this.cachedAuthorization.expiresAt > now + 60) {
      return this.cachedAuthorization.value;
    }
    const encodedHeader = encodeJSON({ alg: "ES256", kid: this.config.keyId, typ: "JWT" });
    const encodedPayload = encodeJSON({ iss: this.config.teamId, iat: now });
    const signingInput = `${encodedHeader}.${encodedPayload}`;
    const signature = sign("sha256", Buffer.from(signingInput), {
      key: this.config.privateKey,
      dsaEncoding: "ieee-p1363",
    });
    const value = `${signingInput}.${signature.toString("base64url")}`;
    this.cachedAuthorization = { value, expiresAt: now + 30 * 60 };
    return value;
  }
}

function encodeJSON(value: unknown): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}
