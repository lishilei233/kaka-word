import type { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { contentDocuments, isContentKey } from "../content/documents.js";

export function registerContentRoute(app: Hono<AppEnv>): void {
  app.get("/v1/content/:key", (c) => {
    const key = c.req.param("key");
    if (!isContentKey(key)) {
      return c.json({ error: "CONTENT_NOT_FOUND", message: "内容不存在" }, 404);
    }

    c.header("Cache-Control", "public, max-age=300, must-revalidate");
    return c.json(contentDocuments[key]);
  });
}
