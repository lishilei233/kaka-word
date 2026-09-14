import type { Context } from "hono";
import { timingSafeEqual } from "node:crypto";
import type { AccessPrincipal, AccessService } from "../core/access/index.js";
import type { AppEnv } from "../app.js";

export async function authenticateAccess(
  c: Context<AppEnv>,
  accessService: AccessService,
): Promise<AccessPrincipal | null> {
  return await accessService.authenticate(c.req.header("authorization"));
}

export function unauthorized(c: Context<AppEnv>) {
  return c.json({ error: "UNAUTHORIZED", message: "访问凭证已失效，请重新打开应用" }, 401);
}

export function authenticateVideoStudio(rawAuthorization: string | undefined, configuredToken: string | undefined): boolean {
  if (!configuredToken || !rawAuthorization?.startsWith("Bearer ")) return false;
  const supplied = Buffer.from(rawAuthorization.slice(7), "utf8");
  const expected = Buffer.from(configuredToken, "utf8");
  return supplied.length === expected.length && timingSafeEqual(supplied, expected);
}
