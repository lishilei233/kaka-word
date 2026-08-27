import assert from "node:assert/strict";
import test from "node:test";
import { monthlyQuotaPeriod } from "./quota-period.js";

test("clamps a January 31 anchor to February and returns to March 31", () => {
  const anchor = new Date("2025-01-31T10:30:00.000Z");
  assert.deepEqual(monthlyQuotaPeriod(anchor, new Date("2025-02-20T00:00:00.000Z")), {
    start: new Date("2025-01-31T10:30:00.000Z"),
    end: new Date("2025-02-28T10:30:00.000Z"),
  });
  assert.deepEqual(monthlyQuotaPeriod(anchor, new Date("2025-03-15T00:00:00.000Z")), {
    start: new Date("2025-02-28T10:30:00.000Z"),
    end: new Date("2025-03-31T10:30:00.000Z"),
  });
});

test("handles leap years and exact reset instants", () => {
  const anchor = new Date("2024-01-31T00:00:00.000Z");
  assert.deepEqual(monthlyQuotaPeriod(anchor, new Date("2024-02-29T00:00:00.000Z")), {
    start: new Date("2024-02-29T00:00:00.000Z"),
    end: new Date("2024-03-31T00:00:00.000Z"),
  });
});

test("keeps the purchase time while crossing a year boundary", () => {
  const anchor = new Date("2025-12-12T23:59:59.123Z");
  assert.deepEqual(monthlyQuotaPeriod(anchor, new Date("2026-01-20T00:00:00.000Z")), {
    start: new Date("2026-01-12T23:59:59.123Z"),
    end: new Date("2026-02-12T23:59:59.123Z"),
  });
});
