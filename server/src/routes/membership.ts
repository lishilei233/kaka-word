import type { Hono } from "hono";
import type { AppEnv } from "../app.js";
import type { AccessConfig } from "../config.js";

export type MembershipConfigResponse = {
  quota: {
    limit: number;
    unlimited: boolean;
  };
};

export function registerMembershipRoute(app: Hono<AppEnv>, accessConfig: AccessConfig): void {
  app.get("/v1/membership/config", (c) => {
    c.header("Cache-Control", "public, max-age=300, must-revalidate");
    const response: MembershipConfigResponse = {
      quota: {
        limit: accessConfig.memberQuotaDefault ?? 100,
        unlimited: accessConfig.memberQuotaUnlimited === true,
      },
    };
    return c.json(response);
  });
}
