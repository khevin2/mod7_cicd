const { SpanStatusCode, trace } = require('@opentelemetry/api');

const TRACE_ID_PATTERN = /^[0-9a-f]{32}$/;
const SPAN_ID_PATTERN = /^[0-9a-f]{16}$/;
const SAMPLED_TRACE_FLAG = 0x01;

function isValidTraceContext(spanContext) {
  return Boolean(
    spanContext &&
    TRACE_ID_PATTERN.test(spanContext.traceId) &&
    SPAN_ID_PATTERN.test(spanContext.spanId) &&
    spanContext.traceId !== '00000000000000000000000000000000' &&
    spanContext.spanId !== '0000000000000000' &&
    (spanContext.traceFlags & SAMPLED_TRACE_FLAG) === SAMPLED_TRACE_FLAG
  );
}

function captureTraceContext(activeSpan = trace.getActiveSpan()) {
  const spanContext = activeSpan?.spanContext?.();
  if (!isValidTraceContext(spanContext)) return undefined;

  return Object.freeze({
    traceId: spanContext.traceId,
    spanId: spanContext.spanId
  });
}

function getLogTraceFields(traceContext = captureTraceContext()) {
  return {
    trace_id: traceContext?.traceId || null,
    span_id: traceContext?.spanId || null
  };
}

function recordSanitizedError(errorType = 'internal_error', activeSpan = trace.getActiveSpan()) {
  if (!activeSpan || !captureTraceContext(activeSpan)) return;
  activeSpan.setStatus({ code: SpanStatusCode.ERROR, message: errorType });
  activeSpan.addEvent('exception', { 'exception.type': errorType });
}

module.exports = {
  captureTraceContext,
  getLogTraceFields,
  isValidTraceContext,
  recordSanitizedError
};
