/**
 * Extracts complete object values from a top-level JSON `objects` array while
 * the surrounding JSON document is still arriving in arbitrary fragments.
 */
export class ObjectArrayStreamParser {
    buffer = "";
    scanIndex = 0;
    foundArray = false;
    objectStart = -1;
    objectDepth = 0;
    inString = false;
    escaped = false;
    push(fragment) {
        this.buffer += fragment;
        const objects = [];
        if (!this.foundArray) {
            const match = /"objects"\s*:\s*\[/.exec(this.buffer);
            if (!match)
                return objects;
            this.foundArray = true;
            this.scanIndex = match.index + match[0].length;
        }
        for (let index = this.scanIndex; index < this.buffer.length; index += 1) {
            const character = this.buffer[index];
            if (this.inString) {
                if (this.escaped) {
                    this.escaped = false;
                }
                else if (character === "\\") {
                    this.escaped = true;
                }
                else if (character === '"') {
                    this.inString = false;
                }
                continue;
            }
            if (character === '"') {
                this.inString = true;
                continue;
            }
            if (this.objectStart < 0) {
                if (character === "{") {
                    this.objectStart = index;
                    this.objectDepth = 1;
                }
                continue;
            }
            if (character === "{") {
                this.objectDepth += 1;
            }
            else if (character === "}") {
                this.objectDepth -= 1;
                if (this.objectDepth === 0) {
                    objects.push(JSON.parse(this.buffer.slice(this.objectStart, index + 1)));
                    this.objectStart = -1;
                }
            }
        }
        this.scanIndex = this.buffer.length;
        return objects;
    }
}
/** Decodes data payloads from an SSE response whose chunks may split lines. */
export async function* readSSEData(body) {
    const reader = body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    try {
        while (true) {
            const { value, done } = await reader.read();
            buffer += decoder.decode(value, { stream: !done });
            buffer = buffer.replace(/\r\n/g, "\n");
            let boundary = buffer.indexOf("\n\n");
            while (boundary >= 0) {
                const block = buffer.slice(0, boundary);
                buffer = buffer.slice(boundary + 2);
                const data = block
                    .split("\n")
                    .filter((line) => line.startsWith("data:"))
                    .map((line) => line.slice(5).trimStart())
                    .join("\n");
                if (data)
                    yield data;
                boundary = buffer.indexOf("\n\n");
            }
            if (done)
                break;
        }
        const data = buffer
            .split("\n")
            .filter((line) => line.startsWith("data:"))
            .map((line) => line.slice(5).trimStart())
            .join("\n");
        if (data)
            yield data;
    }
    finally {
        reader.releaseLock();
    }
}
