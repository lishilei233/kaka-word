import type { Hono } from "hono";
import type { AppEnv } from "../app.js";
import type { AppVersionConfig } from "../config.js";

export function registerAppVersionRoute(app: Hono<AppEnv>, config: AppVersionConfig): void {
  app.get("/v1/app-version", (c) => {
    c.header("Cache-Control", "no-store");
    return c.json(config);
  });
}
