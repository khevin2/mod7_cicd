#!/usr/bin/env node
'use strict';

// Dependency-free PDF renderer. Keeping this self-contained means the two-page
// reviewer artifact can be regenerated from a clean npm install.
const fs = require('fs');
const path = require('path');

const output = path.resolve(__dirname, '../docs/observability-security-report.pdf');
const pages = [
  [
    ['MODULE 10  /  ADVANCED OBSERVABILITY', 8, 48, 812, true],
    ['Observability report', 22, 48, 782, true],
    ['Repository-verified design; not uncaptured runtime evidence.', 9, 48, 762],
    ['ARCHITECTURE AND TELEMETRY FLOW', 9, 48, 718, true],
    ['jenkins-webapp emits bounded RED metrics and structured JSON logs.', 9, 48, 696],
    ['Prometheus privately scrapes metrics, evaluates recording rules, and', 9, 48, 682],
    ['supplies Grafana panels and alerts. OpenTelemetry HTTP and Express', 9, 48, 668],
    ['instrumentation creates server/client spans; sampled traces export via', 9, 48, 654],
    ['private OTLP/HTTP to Jaeger. Grafana opens Jaeger from exemplars.', 9, 48, 640],
    ['symptom -> alert -> RED metric/exemplar -> Jaeger trace/span ->', 10, 48, 608, true],
    ['CloudWatch JSON log -> controlled root cause', 10, 48, 594, true],
    ['RED DEFINITIONS AND EXACT ALERT POLICY', 9, 48, 552, true],
    ['Rate: jenkins_webapp_http_requests_total (dashboard).', 9, 48, 530],
    ['Errors: 5xx / all requests over 5 minutes. Alert: >5%, at least 20', 9, 48, 516],
    ['requests, sustained 10 minutes. Duration: p95 histogram over 5 minutes.', 9, 48, 502],
    ['Alert: >300 ms, at least 20 requests, sustained 10 minutes.', 9, 48, 488],
    ['Grafana evaluates the group every 10 seconds and is the sole alert engine.', 9, 48, 474],
    ['EXPORTER, SAMPLING, PRIVACY, AND CARDINALITY', 9, 48, 430, true],
    ['Only a credential-free RFC1918 OTLP endpoint on TCP 4318 is accepted.', 9, 48, 408],
    ['Sampling is parentbased_traceidratio at 100% for this lab. Exemplars', 9, 48, 394],
    ['carry sampled IDs without adding metric labels. Metrics use only method,', 9, 48, 380],
    ['route, and status-code labels. Logs allowlist operational fields and', 9, 48, 366],
    ['exclude request bodies, headers, cookies, tokens, query values, and', 9, 48, 352],
    ['arbitrary errors. Invalid production exporter configuration fails startup;', 9, 48, 338],
    ['local development/tests default to no exporter.', 9, 48, 324]
  ],
  [
    ['MODULE 10  /  ADVANCED OBSERVABILITY', 8, 48, 812, true],
    ['Controlled acceptance', 22, 48, 782, true],
    ['Live Module 10 acceptance evidence is pending.', 9, 48, 762],
    ['CONTROLLED INCIDENT ANALYSIS - CURRENT STATUS', 9, 48, 718, true],
    ['No deployed Module 10 symptom, alert timestamp, Grafana exemplar, Jaeger', 9, 48, 696],
    ['span, or exact CloudWatch trace_id/span_id match has been captured.', 9, 48, 682],
    ['Do not infer a live incident or successful alert test from local checks.', 9, 48, 668],
    ['REQUIRED USER-OPERATED CAPTURE AND READ-ONLY VERIFICATION', 9, 48, 624, true],
    ['1. Capture a 10-minute normal baseline: rate, p95, errors, CPU, memory,', 9, 48, 602],
    ['   scrape health, and no firing Module 10 alert.', 9, 48, 588],
    ['2. Run POST /test value: error through Pending, Firing, and Resolved.', 9, 48, 574],
    ['3. Separately run value: latency (a fixed 400 ms successful response).', 9, 48, 560],
    ['4. Open an exemplar; inspect matching Jaeger server/client spans and', 9, 48, 546],
    ['   exact-filter CloudWatch JSON logs by trace_id and span_id.', 9, 48, 532],
    ['5. Stop test traffic; verify recovery, ordinary traces, health, and versions.', 9, 48, 518],
    ['CONTROLLED ROOT CAUSE AND REMEDIATION', 9, 48, 474, true],
    ['Error mode deliberately returns HTTP 500; latency mode deliberately delays', 9, 48, 452],
    ['the response by 400 ms. Remediate by stopping test traffic and confirming', 9, 48, 438],
    ['recovery, never by suppressing or bypassing the alert.', 9, 48, 424],
    ['FINAL ACCEPTANCE AND RETAINED STATE', 9, 48, 380, true],
    ['Repository gates verify tracing, RED metrics/exemplars, Jaeger/Grafana', 9, 48, 358],
    ['provisioning, both alert rules, and removal of temporary routes/controller.', 9, 48, 344],
    ['POST /test remains the documented demo route. Live proof remains required.', 9, 48, 330],
    ['Limits: Jaeger storage is non-durable/lab-scoped; 100% sampling is lab-only;', 9, 48, 288],
    ['database tracing is N/A. Store only sanitized evidence in evidence/mod10/.', 9, 48, 274],
    ['2 of 2', 8, 48, 42]
  ]
];

function escapePdf(value) { return value.replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)'); }
function stream(lines) {
  return lines.map(([value, size, x, y, bold]) => `BT /${bold ? 'F2' : 'F1'} ${size} Tf ${x} ${y} Td (${escapePdf(value)}) Tj ET`).join('\n');
}
const objects = [
  '<< /Type /Catalog /Pages 2 0 R >>',
  '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>',
  '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 7 0 R /F2 8 0 R >> >> /Contents 4 0 R >>',
  `<< /Length ${Buffer.byteLength(stream(pages[0]))} >>\nstream\n${stream(pages[0])}\nendstream`,
  '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 7 0 R /F2 8 0 R >> >> /Contents 6 0 R >>',
  `<< /Length ${Buffer.byteLength(stream(pages[1]))} >>\nstream\n${stream(pages[1])}\nendstream`,
  '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>'
];
let pdf = '%PDF-1.4\n';
const offsets = [0];
objects.forEach((object, index) => { offsets.push(Buffer.byteLength(pdf)); pdf += `${index + 1} 0 obj\n${object}\nendobj\n`; });
const xref = Buffer.byteLength(pdf);
pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
offsets.slice(1).forEach((offset) => { pdf += `${String(offset).padStart(10, '0')} 00000 n\n`; });
pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
fs.writeFileSync(output, pdf);
