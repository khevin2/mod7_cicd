const net = require('node:net');

const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-proto');
const { HttpInstrumentation } = require('@opentelemetry/instrumentation-http');
const { ExpressInstrumentation, ExpressLayerType } = require('@opentelemetry/instrumentation-express');
const { resourceFromAttributes } = require('@opentelemetry/resources');
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { ParentBasedSampler, TraceIdRatioBasedSampler } = require('@opentelemetry/sdk-trace-base');

const SERVICE_NAME = 'jenkins-webapp';
const DEPLOYMENT_ENVIRONMENT = 'lab';
const DEFAULT_SERVICE_VERSION = require('../package.json').version;
const OTLP_HTTP_TRACES_PATH = '/v1/traces';

let telemetrySdk;

function isIgnoredIncomingRequest(request) {
  const path = request.url?.split('?', 1)[0];
  return path === '/health' || path === '/metrics';
}

function parseSamplingRatio(value) {
  if (value === undefined || value === '') return 1;
  const ratio = Number(value);
  if (!Number.isFinite(ratio) || ratio < 0 || ratio > 1) {
    throw new Error('OTEL_TRACES_SAMPLER_ARG must be a number between 0 and 1');
  }
  return ratio;
}

function parseResourceAttributes(value, serviceVersion) {
  if (value === undefined || value === '') return {};

  const attributes = {};
  for (const entry of value.split(',')) {
    const separator = entry.indexOf('=');
    if (separator <= 0 || separator === entry.length - 1) {
      throw new Error('OTEL_RESOURCE_ATTRIBUTES must contain comma-separated key=value pairs');
    }
    const key = entry.slice(0, separator).trim();
    const attributeValue = entry.slice(separator + 1).trim();
    if (!key || !attributeValue || Object.hasOwn(attributes, key)) {
      throw new Error('OTEL_RESOURCE_ATTRIBUTES contains an empty or duplicate attribute');
    }
    attributes[key] = attributeValue;
  }

  const expectedAttributes = {
    'service.name': SERVICE_NAME,
    'service.version': serviceVersion,
    'deployment.environment': DEPLOYMENT_ENVIRONMENT
  };
  for (const [key, attributeValue] of Object.entries(attributes)) {
    if (expectedAttributes[key] !== attributeValue) {
      throw new Error(`OTEL_RESOURCE_ATTRIBUTES may only restate the required non-secret resource attributes; invalid ${key}`);
    }
  }
  return attributes;
}

function validatePrivateOtlpEndpoint(value) {
  if (value === undefined || value === '') {
    throw new Error('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT is required when OTEL_TRACES_EXPORTER=otlp');
  }

  let endpoint;
  try {
    endpoint = new URL(value);
  } catch {
    throw new Error('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT must be a valid URL');
  }

  if (endpoint.protocol !== 'http:' || endpoint.username || endpoint.password || endpoint.search || endpoint.hash) {
    throw new Error('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT must be a credential-free private HTTP URL');
  }
  if (!net.isIPv4(endpoint.hostname) || !isPrivateIpv4(endpoint.hostname)) {
    throw new Error('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT must use a private IPv4 address');
  }
  if (endpoint.port !== '4318' || endpoint.pathname !== OTLP_HTTP_TRACES_PATH) {
    throw new Error(`OTEL_EXPORTER_OTLP_TRACES_ENDPOINT must target private TCP 4318 at ${OTLP_HTTP_TRACES_PATH}`);
  }
  return endpoint.toString();
}

function isPrivateIpv4(hostname) {
  const [first, second] = hostname.split('.').map(Number);
  return first === 10 || (first === 172 && second >= 16 && second <= 31) || (first === 192 && second === 168);
}

function readTelemetryConfig(environment = process.env) {
  const serviceVersion = environment.SERVICE_VERSION || environment.IMAGE_VERSION || DEFAULT_SERVICE_VERSION;
  if (!/^[0-9A-Za-z][0-9A-Za-z._-]{0,127}$/.test(serviceVersion)) {
    throw new Error('SERVICE_VERSION must be a non-secret build or image version');
  }
  if (environment.OTEL_SERVICE_NAME && environment.OTEL_SERVICE_NAME !== SERVICE_NAME) {
    throw new Error(`OTEL_SERVICE_NAME must be ${SERVICE_NAME}`);
  }
  if (environment.OTEL_TRACES_SAMPLER && environment.OTEL_TRACES_SAMPLER !== 'parentbased_traceidratio') {
    throw new Error('OTEL_TRACES_SAMPLER must be parentbased_traceidratio when supplied');
  }
  if (environment.OTEL_EXPORTER_OTLP_PROTOCOL && environment.OTEL_EXPORTER_OTLP_PROTOCOL !== 'http/protobuf') {
    throw new Error('OTEL_EXPORTER_OTLP_PROTOCOL must be http/protobuf when supplied');
  }

  const isProduction = environment.NODE_ENV === 'production';
  const tracesExporter = environment.OTEL_TRACES_EXPORTER || 'none';
  if (tracesExporter !== 'none' && tracesExporter !== 'otlp') {
    throw new Error('OTEL_TRACES_EXPORTER must be either none or otlp');
  }
  if (isProduction && tracesExporter !== 'otlp') {
    throw new Error('Production requires OTEL_TRACES_EXPORTER=otlp and an explicitly supplied private endpoint');
  }
  if (tracesExporter === 'none' && environment.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT) {
    throw new Error('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT requires OTEL_TRACES_EXPORTER=otlp');
  }

  return {
    deploymentEnvironment: DEPLOYMENT_ENVIRONMENT,
    endpoint: tracesExporter === 'otlp' ? validatePrivateOtlpEndpoint(environment.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT) : undefined,
    resourceAttributes: parseResourceAttributes(environment.OTEL_RESOURCE_ATTRIBUTES, serviceVersion),
    samplingRatio: parseSamplingRatio(environment.OTEL_TRACES_SAMPLER_ARG),
    serviceName: SERVICE_NAME,
    serviceVersion,
    tracesExporter
  };
}

function initializeTelemetry(environment = process.env, overrides = {}) {
  if (telemetrySdk) return telemetrySdk;

  const config = readTelemetryConfig(environment);
  const options = {
    resource: resourceFromAttributes({
      'service.name': config.serviceName,
      'service.version': config.serviceVersion,
      'deployment.environment': config.deploymentEnvironment
    }),
    sampler: new ParentBasedSampler({ root: new TraceIdRatioBasedSampler(config.samplingRatio) }),
    // This application owns its Prometheus metrics and stdout JSON logs. Empty
    // providers prevent the Node SDK from selecting its default OTLP exporters.
    metricReaders: [],
    logRecordProcessors: [],
    instrumentations: [
      new HttpInstrumentation({ ignoreIncomingRequestHook: isIgnoredIncomingRequest }),
      // HTTP owns the request/server span. Keep Express request-handler spans
      // for route visibility, while suppressing noisy middleware spans so the
      // request correlation context is the stable server span.
      new ExpressInstrumentation({ ignoreLayersType: [ExpressLayerType.MIDDLEWARE] })
    ],
    ...overrides
  };

  if (overrides.spanProcessors) {
    // A deterministic in-memory processor is used only by local tests.
  } else if (config.tracesExporter === 'otlp') {
    options.traceExporter = new OTLPTraceExporter({ url: config.endpoint });
  } else {
    // Supplying an empty processor list prevents the SDK's default localhost
    // exporter. This keeps unit tests and local development network-silent.
    options.spanProcessors = [];
  }

  telemetrySdk = new NodeSDK(options);
  telemetrySdk.start();
  return telemetrySdk;
}

async function shutdownTelemetry() {
  if (!telemetrySdk) return;
  const sdk = telemetrySdk;
  telemetrySdk = undefined;
  await sdk.shutdown();
}

module.exports = {
  DEPLOYMENT_ENVIRONMENT,
  OTLP_HTTP_TRACES_PATH,
  SERVICE_NAME,
  initializeTelemetry,
  isIgnoredIncomingRequest,
  isPrivateIpv4,
  readTelemetryConfig,
  shutdownTelemetry,
  validatePrivateOtlpEndpoint
};
