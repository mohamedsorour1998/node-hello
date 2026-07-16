'use strict';

/**
 * New Relic agent configuration.
 *
 * Every value is driven by environment variables so that NO secrets are ever
 * committed to the repository. The license key is supplied at runtime via
 * NEW_RELIC_LICENSE_KEY (see .env.example / Terraform variables / GitHub
 * Actions secret).
 *
 * Docs: https://docs.newrelic.com/docs/apm/agents/nodejs-agent/installation-configuration/nodejs-agent-configuration/
 */
exports.config = {
  app_name: [process.env.NEW_RELIC_APP_NAME || 'node-hello'],
  license_key: process.env.NEW_RELIC_LICENSE_KEY,

  // Write the agent's own diagnostic log to stdout so it is captured by the
  // container log driver instead of a file inside the container.
  logging: {
    level: process.env.NEW_RELIC_LOG_LEVEL || 'info',
    filepath: process.env.NEW_RELIC_LOG || 'stdout',
  },

  // Forward the application's stdout logs to New Relic (log aggregation).
  application_logging: {
    enabled: true,
    forwarding: {
      enabled: true,
      max_samples_stored: 10000,
    },
    metrics: {
      enabled: true,
    },
  },

  distributed_tracing: {
    enabled: true,
  },

  allow_all_headers: true,
  attributes: {
    exclude: [
      'request.headers.cookie',
      'request.headers.authorization',
      'request.headers.proxyAuthorization',
      'request.headers.setCookie*',
      'request.headers.x*',
      'response.headers.cookie',
      'response.headers.authorization',
      'response.headers.proxyAuthorization',
      'response.headers.setCookie*',
      'response.headers.x*',
    ],
  },
};
