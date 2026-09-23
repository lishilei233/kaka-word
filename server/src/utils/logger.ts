export type LogLevel = "debug" | "info" | "warn" | "error";
export type LogFields = Record<string, unknown>;

export type Logger = {
  debug(event: string, fields?: LogFields): void;
  info(event: string, fields?: LogFields): void;
  warn(event: string, fields?: LogFields): void;
  error(event: string, fields?: LogFields): void;
};

const priorities: Record<LogLevel, number> = { debug: 10, info: 20, warn: 30, error: 40 };

export function createLogger(configuredLevel: LogLevel): Logger {
  function write(level: LogLevel, event: string, fields: LogFields = {}): void {
    if (priorities[level] < priorities[configuredLevel]) return;

    const line = JSON.stringify({ timestamp: new Date().toISOString(), level, event, ...fields });
    if (level === "error") console.error(line);
    else if (level === "warn") console.warn(line);
    else console.log(line);
  }

  return {
    debug: (event, fields) => write("debug", event, fields),
    info: (event, fields) => write("info", event, fields),
    warn: (event, fields) => write("warn", event, fields),
    error: (event, fields) => write("error", event, fields),
  };
}

export function errorFields(error: unknown, includeStack = false): LogFields {
  if (!(error instanceof Error)) return { errorType: "UnknownError", errorMessage: "Unknown error" };

  const cause = error.cause;

  return {
    errorType: error.name,
    errorMessage: redactSecrets(error.message),
    ...(includeStack && error.stack ? { stack: redactSecrets(error.stack) } : {}),
    ...causeFields(cause, includeStack),
  };
}

function causeFields(cause: unknown, includeStack: boolean): LogFields {
  if (cause == null) return {};

  if (cause instanceof Error) {
    const systemCause = cause as Error & {
      code?: unknown;
      errno?: unknown;
      syscall?: unknown;
      address?: unknown;
      port?: unknown;
    };
    return {
      causeType: cause.name,
      causeMessage: redactSecrets(cause.message),
      ...scalarField("causeCode", systemCause.code),
      ...scalarField("causeErrno", systemCause.errno),
      ...scalarField("causeSyscall", systemCause.syscall),
      ...scalarField("causeAddress", systemCause.address),
      ...scalarField("causePort", systemCause.port),
      ...(includeStack && cause.stack ? { causeStack: redactSecrets(cause.stack) } : {}),
    };
  }

  return {
    causeType: typeof cause,
    causeMessage: redactSecrets(String(cause)),
  };
}

function scalarField(name: string, value: unknown): LogFields {
  return typeof value === "string" || typeof value === "number"
    ? { [name]: value }
    : {};
}

function redactSecrets(value: string): string {
  return value
    .replace(/Bearer\s+[^\s"']+/gi, "Bearer [REDACTED]")
    .replace(/sk-[A-Za-z0-9._-]+/g, "sk-[REDACTED]");
}
