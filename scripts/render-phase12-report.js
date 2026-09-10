#!/usr/bin/env node
'use strict';

// Dependency-free vector renderer for the required two-page assurance report.
// One muted blue accent and neutral tones keep the document publication-like.
const fs = require('fs');
const path = require('path');

const output = path.resolve(__dirname, '../docs/observability-security-report.pdf');
const W = 595;
const H = 842;
const M = 42;
const R = W - M;

const C = {
  paper: '#FFFFFF',
  ink: '#20262D',
  muted: '#626B73',
  line: '#D8DDE2',
  accent: '#23527C'
};

function rgb(hex) {
  const clean = hex.slice(1);
  return [0, 2, 4].map(function (index) {
    return (parseInt(clean.slice(index, index + 2), 16) / 255).toFixed(3);
  }).join(' ');
}

function esc(value) {
  return String(value)
    .replace(/\\/g, '\\\\')
    .replace(/\(/g, '\\(')
    .replace(/\)/g, '\\)');
}

function makePage() {
  const commands = [];

  function add(command) {
    commands.push(command);
  }

  function rect(x, y, width, height, fill, stroke, lineWidth) {
    const outline = stroke ? ' ' + rgb(stroke) + ' RG ' + (lineWidth || 1) + ' w' : '';
    add('q ' + rgb(fill) + ' rg' + outline + ' ' + x + ' ' + y + ' ' + width + ' ' + height + ' re ' + (stroke ? 'B' : 'f') + ' Q');
  }

  function line(x1, y1, x2, y2, color, lineWidth) {
    add('q ' + rgb(color || C.line) + ' RG ' + (lineWidth || 1) + ' w ' + x1 + ' ' + y1 + ' m ' + x2 + ' ' + y2 + ' l S Q');
  }

  function text(value, x, y, size, options) {
    options = options || {};
    const font = options.bold ? 'F2' : 'F1';
    const tracking = options.tracking ? options.tracking + ' Tc ' : '';
    add('BT /' + font + ' ' + (size || 9) + ' Tf ' + rgb(options.color || C.ink) + ' rg ' + tracking + x + ' ' + y + ' Td (' + esc(value) + ') Tj ET');
  }

  function wrap(value, x, y, maxWidth, size, options) {
    options = options || {};
    const words = String(value).split(/\s+/);
    const lines = [];
    let current = '';
    const widthFactor = options.bold ? 0.54 : 0.49;

    words.forEach(function (word) {
      const candidate = current ? current + ' ' + word : word;
      if (candidate.length * size * widthFactor > maxWidth && current) {
        lines.push(current);
        current = word;
      } else {
        current = candidate;
      }
    });
    if (current) lines.push(current);

    const shown = options.maxLines ? lines.slice(0, options.maxLines) : lines;
    const leading = options.leading || size * 1.42;
    shown.forEach(function (entry, index) {
      text(entry, x, y - index * leading, size, options);
    });
    return y - shown.length * leading;
  }

  function ruleLabel(label, y) {
    text(label.toUpperCase(), M, y, 7.3, { bold: true, color: C.accent, tracking: 0.75 });
    line(M, y - 9, R, y - 9, C.line, 0.8);
  }

  function finding(number, title, body, y) {
    text(number, M, y, 8.5, { bold: true, color: C.accent });
    text(title, M + 27, y, 9.6, { bold: true });
    wrap(body, M + 154, y, R - (M + 154), 9.2, { color: C.muted, leading: 12.2, maxLines: 2 });
  }

  function footer(page, descriptor) {
    line(M, 38, R, 38, C.line, 0.8);
    text('MODULE 10  |  OBSERVABILITY REPORT', M, 22, 7, { bold: true, color: C.muted, tracking: 0.4 });
    text(descriptor, 223, 22, 7, { color: C.muted });
    text(String(page) + ' / 2', 531, 22, 7, { bold: true, color: C.accent });
  }

  return { commands, rect, line, text, wrap, ruleLabel, finding, footer };
}

function reportHeader(p, pageTitle, pageDescriptor) {
  p.rect(0, 0, W, H, C.paper);
  p.rect(0, H - 8, W, 8, C.accent);
  p.text(pageTitle, M, 782, 26, { bold: true });
  p.text(pageDescriptor, M, 756, 10, { color: C.muted });
  p.line(M, 731, R, 731, C.ink, 1.1);
}

function pageOne() {
  const p = makePage();
  reportHeader(
    p,
    'Observability assurance report',
    'Module 10 | Monitoring, distributed tracing and incident correlation'
  );

  p.ruleLabel('Executive summary', 694);
  p.wrap(
    'The implementation meets the Module 10 acceptance objective. RED metrics, guarded alerts, distributed traces and structured logs form a coherent investigation path from a service symptom to its controlled root cause.',
    M, 667, R - M, 9.7, { leading: 13.5, maxLines: 3 }
  );
  p.wrap(
    'Retained deployment evidence confirms the alert lifecycle, cross-tool identifier matching and return to a healthy state. The design also bounds metric cardinality and excludes sensitive request data from telemetry.',
    M, 619, R - M, 9.7, { leading: 13.5, maxLines: 3 }
  );

  p.ruleLabel('Key findings', 567);
  p.finding('01', 'Actionable alerting', 'Grafana evaluates guarded error-rate and latency rules every 10 seconds; a breach must persist for 10 minutes.', 539);
  p.line(M + 27, 508, R, 508, C.line, 0.6);
  p.finding('02', 'End-to-end correlation', 'The exemplar trace ID resolves to Jaeger; the trace and span IDs then locate the exact CloudWatch JSON log.', 490);
  p.line(M + 27, 459, R, 459, C.line, 0.6);
  p.finding('03', 'Bounded telemetry', 'Metric labels and log fields are allowlisted, while trace export is credential-free and limited to a private receiver.', 441);

  p.ruleLabel('Investigation path', 395);
  const stages = [
    ['01', 'Symptom', 'Grafana'],
    ['02', 'Alert', 'Grafana'],
    ['03', 'Exemplar', 'Prometheus'],
    ['04', 'Trace / span', 'Jaeger'],
    ['05', 'Correlated log', 'CloudWatch']
  ];
  stages.forEach(function (stage, index) {
    const x = M + index * 102;
    p.text(stage[0], x, 364, 7, { bold: true, color: C.accent });
    p.text(stage[1], x, 348, 8.5, { bold: true });
    p.text(stage[2], x, 334, 7.8, { color: C.muted });
    if (index < stages.length - 1) {
      p.line(x + 80, 362, x + 94, 362, C.line, 1);
    }
  });
  p.text('Correlation key', M, 304, 7.2, { bold: true, color: C.muted });
  p.text('Sampled W3C trace ID; span ID identifies the exact operation.', M + 72, 304, 8.5);

  p.ruleLabel('RED signal and alert policy', 269);
  p.rect(M, 217, R - M, 23, C.line);
  p.text('SIGNAL', M + 10, 225, 7, { bold: true });
  p.text('MEASUREMENT', M + 90, 225, 7, { bold: true });
  p.text('POLICY', M + 335, 225, 7, { bold: true });
  p.line(M, 194, R, 194, C.line, 0.6);
  p.line(M, 171, R, 171, C.line, 0.6);
  p.line(M, 148, R, 148, C.line, 0.6);
  [
    ['Rate', 'Total requests', 'Dashboard baseline'],
    ['Errors', '5xx / all requests over 5 minutes', '> 5%; 20+ requests; 10 minutes'],
    ['Duration', 'p95 histogram over 5 minutes', '> 300 ms; 20+ requests; 10 minutes']
  ].forEach(function (row, index) {
    const y = 202 - index * 23;
    p.text(row[0], M + 10, y, 8.3, { bold: true });
    p.text(row[1], M + 90, y, 8.3, { color: C.muted });
    p.text(row[2], M + 335, y, 8.3, { bold: index > 0 });
  });

  p.text('CONTROL NOTE', M, 122, 6.8, { bold: true, color: C.accent, tracking: 0.55 });
  p.wrap('Labels are limited to method, route and status. Logs exclude bodies, headers, cookies, tokens, query values and arbitrary errors.', M + 92, 122, R - (M + 92), 8.2, { color: C.muted, leading: 10.5, maxLines: 2 });

  p.footer(1, 'OBSERVABILITY DESIGN');
  return p.commands.join('\n');
}

function pageTwo() {
  const p = makePage();
  reportHeader(
    p,
    'Evidence and conclusion',
    'Controlled validation, correlation chain and acceptance boundary'
  );

  p.ruleLabel('Controlled validation', 684);
  p.rect(M, 637, R - M, 23, C.line);
  p.text('TEST', M + 10, 645, 7, { bold: true });
  p.text('OBSERVED EFFECT', M + 130, 645, 7, { bold: true });
  p.text('VERIFICATION AND RECOVERY', M + 286, 645, 7, { bold: true });
  p.line(M, 584, R, 584, C.line, 0.6);
  p.line(M, 530, R, 530, C.line, 0.6);

  p.text('Error mode', M + 10, 618, 9, { bold: true });
  p.text('POST /test | value=error', M + 10, 603, 7.8, { color: C.muted });
  p.text('Deliberate HTTP 500', M + 130, 618, 8.7, { bold: true });
  p.text('Assessed as a bounded run', M + 130, 603, 7.8, { color: C.muted });
  p.wrap('Pending, Firing and Resolved states captured. Stopping controlled traffic restored service.', M + 286, 618, 211, 8.2, { color: C.muted, leading: 11.2, maxLines: 3 });

  p.text('Latency mode', M + 10, 564, 9, { bold: true });
  p.text('POST /test | value=latency', M + 10, 549, 7.8, { color: C.muted });
  p.text('Fixed 400 ms success', M + 130, 564, 8.7, { bold: true });
  p.text('Assessed independently', M + 130, 549, 7.8, { color: C.muted });
  p.wrap('Alert behavior verified without suppression, bypass or configuration change.', M + 286, 564, 211, 8.2, { color: C.muted, leading: 11.2, maxLines: 2 });

  p.ruleLabel('Correlation chain', 495);
  const evidence = [
    ['01', 'Alert state', 'UTC marker'],
    ['02', 'Exemplar', 'Trace ID'],
    ['03', 'Jaeger', 'Matching span'],
    ['04', 'CloudWatch', 'Exact IDs'],
    ['05', 'Root cause', '/test mode']
  ];
  evidence.forEach(function (item, index) {
    const x = M + index * 102;
    p.text(item[0], x, 464, 7, { bold: true, color: C.accent });
    p.text(item[1], x, 448, 8.4, { bold: true });
    p.text(item[2], x, 434, 7.8, { color: C.muted });
    if (index < evidence.length - 1) {
      p.line(x + 80, 462, x + 94, 462, C.line, 1);
    }
  });
  p.wrap('The same identifier links the metric exemplar, Jaeger trace and structured log. Route-stable span names and the selected test mode establish causality.', M, 403, R - M, 9.2, { leading: 12.5, maxLines: 2 });

  p.ruleLabel('Verification sequence', 357);
  [
    ['01', 'Baseline', 'Healthy scrape state and 10-minute normal baseline.'],
    ['02', 'Error mode', 'Bounded 500 traffic; full alert lifecycle captured.'],
    ['03', 'Latency mode', 'Fixed 400 ms successes assessed separately.'],
    ['04', 'Correlate', 'Exemplar, spans and exact log IDs matched.'],
    ['05', 'Recover', 'Ordinary traffic, versions and healthy state reconfirmed.']
  ].forEach(function (step, index) {
    const y = 329 - index * 24;
    p.text(step[0], M, y, 7.5, { bold: true, color: C.accent });
    p.text(step[1], M + 33, y, 8.7, { bold: true });
    p.text(step[2], M + 124, y, 8.7, { color: C.muted });
  });

  p.ruleLabel('Acceptance boundary', 190);
  p.text('PROVEN IN REPOSITORY', M, 162, 7.1, { bold: true, color: C.accent, tracking: 0.45 });
  p.wrap('HTTP server/client spans, RED metrics and exemplars; Jaeger and Grafana provisioning; both alert rules.', M, 143, 235, 8.5, { leading: 11.4, maxLines: 3 });
  p.line(296, 112, 296, 165, C.line, 0.8);
  p.text('VERIFIED IN DEPLOYMENT', 316, 162, 7.1, { bold: true, color: C.accent, tracking: 0.45 });
  p.wrap('Populated panels, alert lifecycles, trace links and exact log IDs; recovery, ordinary traces, health and versions.', 316, 143, 237, 8.5, { leading: 11.4, maxLines: 3 });

  p.line(M, 98, R, 98, C.ink, 1.1);
  p.text('CONCLUSION', M, 78, 7.1, { bold: true, color: C.accent, tracking: 0.55 });
  p.text('Acceptance evidence is complete and the service returned to a healthy state.', M + 84, 78, 9.1, { bold: true });
  p.text('LIMITS', M, 60, 6.8, { bold: true, color: C.muted, tracking: 0.55 });
  p.text('Non-durable lab Jaeger; 100% lab sampling; database tracing not applicable.', M + 84, 60, 8.2, { color: C.muted });

  p.footer(2, 'SANITIZED EVIDENCE  |  evidence/mod10/');
  return p.commands.join('\n');
}

const streams = [pageOne(), pageTwo()];
const objects = [
  '<< /Type /Catalog /Pages 2 0 R /Outlines 10 0 R /PageMode /UseOutlines /Lang (en-ZA) /ViewerPreferences << /DisplayDocTitle true >> >>',
  '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>',
  '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 7 0 R /F2 8 0 R >> >> /Contents 4 0 R >>',
  '<< /Length ' + Buffer.byteLength(streams[0]) + ' >>\nstream\n' + streams[0] + '\nendstream',
  '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 7 0 R /F2 8 0 R >> >> /Contents 6 0 R >>',
  '<< /Length ' + Buffer.byteLength(streams[1]) + ' >>\nstream\n' + streams[1] + '\nendstream',
  '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
  '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>',
  '<< /Title (Observability Assurance Report) /Subject (Module 10 monitoring, distributed tracing and incident correlation) /Keywords (Prometheus, Grafana, Jaeger, OpenTelemetry, CloudWatch) /Creator (Dependency-free Node.js PDF renderer) >>',
  '<< /Type /Outlines /First 11 0 R /Last 12 0 R /Count 2 >>',
  '<< /Title (Observability design) /Parent 10 0 R /Next 12 0 R /Dest [3 0 R /Fit] >>',
  '<< /Title (Evidence and conclusion) /Parent 10 0 R /Prev 11 0 R /Dest [5 0 R /Fit] >>'
];

let pdf = '%PDF-1.4\n%\xE2\xE3\xCF\xD3\n';
const offsets = [0];
objects.forEach(function (object, index) {
  offsets.push(Buffer.byteLength(pdf, 'binary'));
  pdf += (index + 1) + ' 0 obj\n' + object + '\nendobj\n';
});
const xref = Buffer.byteLength(pdf, 'binary');
pdf += 'xref\n0 ' + (objects.length + 1) + '\n0000000000 65535 f \n';
offsets.slice(1).forEach(function (offset) {
  pdf += String(offset).padStart(10, '0') + ' 00000 n \n';
});
pdf += 'trailer\n<< /Size ' + (objects.length + 1) + ' /Root 1 0 R /Info 9 0 R >>\nstartxref\n' + xref + '\n%%EOF\n';

fs.writeFileSync(output, Buffer.from(pdf, 'binary'));
console.log('Rendered ' + output + ' (' + streams.length + ' pages)');
