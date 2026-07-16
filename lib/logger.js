'use strict';

/**
 * Minimal dependency-free structured (JSON) logger.
 *
 * Every log line is a single JSON object written to stdout. This is the
 * format container log drivers and log shippers expect, and the New Relic
 * Node.js agent automatically forwards these application logs to New Relic
 * ("logs in context") when the agent is enabled.
 */

const LEVELS = { debug: 20, info: 30, warn: 40, error: 50 };
const configuredLevel = LEVELS[process.env.LOG_LEVEL] || LEVELS.info;

function log(level, message, meta = {}) {
  const levelValue = LEVELS[level] || LEVELS.info;
  if (levelValue < configuredLevel) return;

  const entry = {
    timestamp: new Date().toISOString(),
    level,
    message,
    ...meta,
  };

  process.stdout.write(`${JSON.stringify(entry)}\n`);
}

module.exports = { log, LEVELS };
