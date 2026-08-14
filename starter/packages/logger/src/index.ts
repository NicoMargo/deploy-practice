export type LogLevel = "debug" | "info" | "warn" | "error";

export interface Logger {
  debug(message: string, fields?: Record<string, unknown>): void;
  info(message: string, fields?: Record<string, unknown>): void;
  warn(message: string, fields?: Record<string, unknown>): void;
  error(message: string, fields?: Record<string, unknown>): void;
}

function emit(level: LogLevel, service: string, message: string, fields?: Record<string, unknown>): void {
  const line = JSON.stringify({
    ts: new Date().toISOString(),
    level,
    service,
    message,
    ...fields,
  });
  if (level === "error") {
    console.error(line);
    return;
  }
  console.log(line);
}

export function createLogger(service: string): Logger {
  return {
    debug: (message, fields) => emit("debug", service, message, fields),
    info: (message, fields) => emit("info", service, message, fields),
    warn: (message, fields) => emit("warn", service, message, fields),
    error: (message, fields) => emit("error", service, message, fields),
  };
}
