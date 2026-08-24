const priorities = {
    debug: 10,
    info: 20,
    warn: 30,
    error: 40,
};
const configuredLevel = parseLogLevel(process.env.LOG_LEVEL);
function parseLogLevel(value) {
    if (value === "debug" || value === "info" || value === "warn" || value === "error") {
        return value;
    }
    return "info";
}
function write(level, event, fields = {}) {
    if (priorities[level] < priorities[configuredLevel])
        return;
    const entry = {
        timestamp: new Date().toISOString(),
        level,
        event,
        ...fields,
    };
    const line = JSON.stringify(entry);
    if (level === "error") {
        console.error(line);
    }
    else if (level === "warn") {
        console.warn(line);
    }
    else {
        console.log(line);
    }
}
export const logger = {
    debug: (event, fields) => write("debug", event, fields),
    info: (event, fields) => write("info", event, fields),
    warn: (event, fields) => write("warn", event, fields),
    error: (event, fields) => write("error", event, fields),
};
export function errorFields(error) {
    if (!(error instanceof Error))
        return { errorType: "UnknownError", errorMessage: "Unknown error" };
    return {
        errorType: error.name,
        errorMessage: redactSecrets(error.message),
        ...(process.env.LOG_LEVEL === "debug" && error.stack
            ? { stack: redactSecrets(error.stack) }
            : {}),
    };
}
function redactSecrets(value) {
    return value
        .replace(/Bearer\s+[^\s"']+/gi, "Bearer [REDACTED]")
        .replace(/sk-[A-Za-z0-9._-]+/g, "sk-[REDACTED]");
}
