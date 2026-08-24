export function extractJson(text) {
    const cleaned = text.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "");
    const start = cleaned.indexOf("{");
    const end = cleaned.lastIndexOf("}");
    if (start < 0 || end <= start)
        throw new Error("Vision provider returned no JSON object");
    return JSON.parse(cleaned.slice(start, end + 1));
}
