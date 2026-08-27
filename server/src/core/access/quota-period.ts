export type QuotaPeriod = { start: Date; end: Date };

/** Returns the monthly window anchored to the original purchase day in UTC. */
export function monthlyQuotaPeriod(anchor: Date, now: Date): QuotaPeriod {
  if (Number.isNaN(anchor.getTime()) || Number.isNaN(now.getTime())) throw new Error("Invalid quota period date");
  if (now < anchor) return { start: new Date(anchor), end: addMonthsClamped(anchor, 1) };

  let monthIndex = (now.getUTCFullYear() - anchor.getUTCFullYear()) * 12
    + now.getUTCMonth() - anchor.getUTCMonth();
  let start = addMonthsClamped(anchor, monthIndex);
  if (start > now) {
    monthIndex -= 1;
    start = addMonthsClamped(anchor, monthIndex);
  }
  let end = addMonthsClamped(anchor, monthIndex + 1);
  if (end <= now) {
    monthIndex += 1;
    start = end;
    end = addMonthsClamped(anchor, monthIndex + 1);
  }
  return { start, end };
}

export function addMonthsClamped(anchor: Date, monthOffset: number): Date {
  const targetMonthStart = new Date(Date.UTC(
    anchor.getUTCFullYear(),
    anchor.getUTCMonth() + monthOffset,
    1,
    anchor.getUTCHours(),
    anchor.getUTCMinutes(),
    anchor.getUTCSeconds(),
    anchor.getUTCMilliseconds(),
  ));
  const daysInMonth = new Date(Date.UTC(
    targetMonthStart.getUTCFullYear(),
    targetMonthStart.getUTCMonth() + 1,
    0,
  )).getUTCDate();
  targetMonthStart.setUTCDate(Math.min(anchor.getUTCDate(), daysInMonth));
  return targetMonthStart;
}
