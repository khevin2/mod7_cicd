#!/usr/bin/env node
'use strict';

// Dependency-free vector PDF renderer for the two-page reviewer report.
const fs = require('fs');
const path = require('path');
const output = path.resolve(__dirname, '../docs/observability-security-report.pdf');
const W = 595;
const H = 842;

const C = {
  paper: '#F6F8FC', white: '#FFFFFF', ink: '#14243A', muted: '#617087', line: '#DCE3EC',
  navy: '#102A43', navy2: '#183B5B', blue: '#2774E6', blueSoft: '#EAF2FF',
  teal: '#138A83', tealSoft: '#E8F7F5', green: '#16835D', greenSoft: '#E9F7F0',
  amber: '#B86600', amberSoft: '#FFF3D6', red: '#B9414B', redSoft: '#FDECEF'
};

function rgb(hex) {
  const clean = hex.slice(1);
  return [0, 2, 4].map((i) => (parseInt(clean.slice(i, i + 2), 16) / 255).toFixed(3)).join(' ');
}
function esc(value) { return value.replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)'); }

function makePage() {
  const commands = [];
  const add = (command) => commands.push(command);
  function rect(x, y, w, h, fill, stroke = null, width = 1) {
    add(`q ${rgb(fill)} rg${stroke ? ` ${rgb(stroke)} RG ${width} w` : ''} ${x} ${y} ${w} ${h} re ${stroke ? 'B' : 'f'} Q`);
  }
  function line(x1, y1, x2, y2, color = C.line, width = 1) {
    add(`q ${rgb(color)} RG ${width} w ${x1} ${y1} m ${x2} ${y2} l S Q`);
  }
  function circle(cx, cy, radius, fill, stroke = null, width = 1) {
    const k = radius * 0.55228475;
    const path = `${cx + radius} ${cy} m ${cx + radius} ${cy + k} ${cx + k} ${cy + radius} ${cx} ${cy + radius} c ${cx - k} ${cy + radius} ${cx - radius} ${cy + k} ${cx - radius} ${cy} c ${cx - radius} ${cy - k} ${cx - k} ${cy - radius} ${cx} ${cy - radius} c ${cx + k} ${cy - radius} ${cx + radius} ${cy - k} ${cx + radius} ${cy} c`;
    add(`q ${rgb(fill)} rg${stroke ? ` ${rgb(stroke)} RG ${width} w` : ''} ${path} ${stroke ? 'B' : 'f'} Q`);
  }
  function text(value, x, y, size = 9, options = {}) {
    const font = options.bold ? 'F2' : 'F1';
    const color = options.color || C.ink;
    const tracking = options.tracking ? `${options.tracking} Tc ` : '';
    add(`BT /${font} ${size} Tf ${rgb(color)} rg ${tracking}${x} ${y} Td (${esc(value)}) Tj ET`);
  }
  function wrap(value, x, y, maxWidth, size = 9, options = {}) {
    const words = value.split(/\s+/); const lines = []; let current = '';
    const factor = options.bold ? 0.56 : 0.50;
    for (const word of words) {
      const candidate = current ? `${current} ${word}` : word;
      if (candidate.length * size * factor > maxWidth && current) { lines.push(current); current = word; } else current = candidate;
    }
    if (current) lines.push(current);
    const leading = options.leading || size * 1.38;
    const shown = options.maxLines ? lines.slice(0, options.maxLines) : lines;
    shown.forEach((entry, index) => text(entry, x, y - index * leading, size, options));
    return y - shown.length * leading;
  }
  function pill(label, x, y, w, fill, color) {
    rect(x, y, w, 20, fill); circle(x, y + 10, 10, fill); circle(x + w, y + 10, 10, fill);
    text(label, x + 8, y + 6.5, 7.4, { bold: true, color, tracking: 0.25 });
  }
  function sectionLabel(label, x, y, color = C.blue) {
    rect(x, y - 1, 4, 14, color);
    text(label.toUpperCase(), x + 12, y + 2, 8, { bold: true, color: C.navy, tracking: 0.7 });
  }
  function arrow(x1, y, x2, color = C.blue) {
    line(x1, y, x2 - 5, y, color, 1.5);
    add(`q ${rgb(color)} rg ${x2 - 7} ${y + 3.5} m ${x2} ${y} l ${x2 - 7} ${y - 3.5} l f Q`);
  }
  function footer(page, label) {
    line(32, 34, 563, 34, C.line, 0.8);
    text('AMALI TECH  /  MODULE 10', 32, 18, 6.8, { bold: true, color: C.muted, tracking: 0.7 });
    text(label, 250, 18, 6.8, { color: C.muted });
    text(`${String(page).padStart(2, '0')} / 02`, 519, 18, 7.2, { bold: true, color: C.navy });
  }
  return { commands, rect, line, circle, text, wrap, pill, sectionLabel, arrow, footer };
}

function header(p, title, subtitle, status, statusWidth, statusFill, statusColor) {
  p.rect(0, 0, W, H, C.paper); p.rect(0, 700, W, 142, C.navy); p.rect(0, 700, 8, 142, C.blue);
  p.text('MODULE 10', 32, 815, 8, { bold: true, color: '#7EB2FF', tracking: 1.2 });
  p.text('ADVANCED OBSERVABILITY', 102, 815, 8, { bold: true, color: C.white, tracking: 1.2 });
  p.text(title, 32, 768, 27, { bold: true, color: C.white });
  p.wrap(subtitle, 32, 742, 390, 9, { color: '#C9D7E5', leading: 12 });
  p.pill(status, 447, 754, statusWidth, statusFill, statusColor);
}

function pageOne() {
  const p = makePage();
  header(p, 'Observability posture', 'Repository and deployed-runtime evidence verified end to end.', 'EVIDENCE VERIFIED', 99, C.greenSoft, C.green);

  [
    { x: 32, value: '> 5%', label: '5xx error ratio', note: '5-minute window', color: C.red },
    { x: 213, value: '> 300 ms', label: 'p95 latency', note: '5-minute window', color: C.amber },
    { x: 394, value: '10 min', label: 'sustained breach', note: 'minimum 20 requests', color: C.teal }
  ].forEach((card) => {
    p.rect(card.x, 632, 169, 52, C.white, C.line, 0.7); p.rect(card.x, 632, 4, 52, card.color);
    p.text(card.value, card.x + 14, 659, 15, { bold: true, color: C.navy });
    p.text(card.label, card.x + 14, 646, 7.2, { bold: true, color: C.muted });
    p.text(card.note, card.x + 92, 646, 6.7, { color: C.muted });
  });

  p.sectionLabel('Architecture & correlation path', 32, 601);
  p.text('A single investigation path joins symptoms to controlled root cause.', 259, 604, 7.5, { color: C.muted });
  const nodes = [
    { x: 32, w: 91, title: 'APPLICATION', body: 'RED + JSON', fill: C.blueSoft, color: C.blue },
    { x: 142, w: 91, title: 'PROMETHEUS', body: 'scrape + rules', fill: C.tealSoft, color: C.teal },
    { x: 252, w: 91, title: 'GRAFANA', body: 'panels + alerts', fill: C.blueSoft, color: C.blue },
    { x: 362, w: 91, title: 'JAEGER', body: 'trace + spans', fill: C.tealSoft, color: C.teal },
    { x: 472, w: 91, title: 'CLOUDWATCH', body: 'exact ID match', fill: C.blueSoft, color: C.blue }
  ];
  nodes.forEach((node, index) => {
    p.rect(node.x, 544, node.w, 40, node.fill); p.circle(node.x + 13, 570, 4, node.color);
    p.text(node.title, node.x + 22, 567, 6.7, { bold: true, color: C.navy, tracking: 0.3 });
    p.text(node.body, node.x + 10, 553, 7, { color: C.muted });
    if (index < nodes.length - 1) p.arrow(node.x + node.w + 3, 564, nodes[index + 1].x - 3, C.blue);
  });
  ['symptom', 'alert', 'exemplar', 'trace / span', 'controlled root cause'].forEach((label, index) => {
    p.text(label, nodes[index].x, 527, 6.6, { bold: true, color: index % 2 ? C.teal : C.blue });
  });

  p.sectionLabel('RED signal policy', 32, 494);
  p.rect(32, 382, 531, 94, C.white, C.line, 0.7); p.rect(32, 452, 531, 24, C.navy2);
  p.text('SIGNAL', 45, 460, 6.7, { bold: true, color: C.white, tracking: 0.5 });
  p.text('DEFINITION', 132, 460, 6.7, { bold: true, color: C.white, tracking: 0.5 });
  p.text('ALERT POLICY', 389, 460, 6.7, { bold: true, color: C.white, tracking: 0.5 });
  p.line(117, 382, 117, 476); p.line(374, 382, 374, 476); p.line(32, 429, 563, 429); p.line(32, 405, 563, 405);
  p.text('RATE', 45, 438, 7.3, { bold: true, color: C.blue });
  p.text('jenkins_webapp_http_requests_total', 132, 438, 7.4); p.text('Dashboard only', 389, 438, 7.4, { color: C.muted });
  p.text('ERRORS', 45, 414, 7.3, { bold: true, color: C.red });
  p.text('5xx / all requests over 5 minutes', 132, 414, 7.4); p.text('>5%  |  20+ req  |  10 min', 389, 414, 7.4, { bold: true });
  p.text('DURATION', 45, 390, 7.3, { bold: true, color: C.amber });
  p.text('p95 histogram over 5 minutes', 132, 390, 7.4); p.text('>300 ms  |  20+ req  |  10 min', 389, 390, 7.4, { bold: true });

  p.sectionLabel('Controls by design', 32, 351);
  p.rect(32, 181, 258, 152, C.white, C.line, 0.7); p.rect(305, 181, 258, 152, C.white, C.line, 0.7);
  p.pill('PRIVACY + CARDINALITY', 48, 297, 121, C.blueSoft, C.blue);
  p.text('Bounded metrics', 48, 276, 9, { bold: true, color: C.navy });
  p.wrap('Labels are limited to method, route and status code. Trace IDs travel as exemplars, never metric labels.', 48, 261, 220, 7.6, { color: C.muted, leading: 11 });
  p.text('Allowlisted logs', 48, 220, 9, { bold: true, color: C.navy });
  p.wrap('No bodies, headers, cookies, tokens, query values or arbitrary error payloads.', 48, 205, 220, 7.6, { color: C.muted, leading: 11 });
  p.pill('EXPORT + SAMPLING', 321, 297, 105, C.tealSoft, C.teal);
  p.text('Private OTLP only', 321, 276, 9, { bold: true, color: C.navy });
  p.wrap('Credential-free RFC1918 endpoint on TCP 4318. Invalid production configuration fails at startup.', 321, 261, 220, 7.6, { color: C.muted, leading: 11 });
  p.text('Lab-scoped sampling', 321, 220, 9, { bold: true, color: C.navy });
  p.wrap('parentbased_traceidratio at 100%. Production must reduce sampling to match volume and retention.', 321, 205, 220, 7.6, { color: C.muted, leading: 11 });

  p.rect(32, 78, 531, 81, C.navy);
  p.text('OPERATING MODEL', 48, 137, 7, { bold: true, color: '#7EB2FF', tracking: 0.7 });
  p.text('Grafana is the sole alert engine.', 48, 117, 12, { bold: true, color: C.white });
  p.wrap('It evaluates every 10 seconds. OpenTelemetry HTTP and Express instrumentation creates server and client spans; Grafana resolves exemplars to Jaeger.', 48, 101, 482, 7.6, { color: '#C9D7E5', leading: 11 });
  p.footer(1, 'OBSERVABILITY & SECURITY REPORT');
  return p.commands.join('\n');
}

function pageTwo() {
  const p = makePage();
  header(p, 'Verified acceptance', 'A complete path from bounded test traffic to confirmed recovery.', 'END-TO-END VERIFIED', 108, C.greenSoft, C.green);
  p.rect(32, 635, 531, 48, C.greenSoft); p.rect(32, 635, 5, 48, C.green);
  p.text('VERIFICATION STATUS', 49, 664, 7, { bold: true, color: C.green, tracking: 0.7 });
  p.wrap('Deployed evidence confirms the alert lifecycle, exemplar, matching Jaeger spans, exact CloudWatch IDs and healthy recovery.', 49, 649, 490, 8.2, { bold: true, color: C.navy, leading: 11 });

  p.sectionLabel('Verified capture sequence', 32, 603, C.green);
  const steps = [
    ['01', 'BASELINE', '10-minute normal baseline and healthy scrape state verified.'],
    ['02', 'ERROR MODE', 'HTTP 500 test observed through Pending, Firing and Resolved.'],
    ['03', 'LATENCY MODE', 'Independent fixed 400 ms successful response validated.'],
    ['04', 'CORRELATE', 'Exemplar, Jaeger spans and exact-match JSON log IDs verified.'],
    ['05', 'RECOVER', 'Ordinary traces, health, versions and alert recovery confirmed.']
  ];
  p.line(52, 415, 52, 574, C.line, 2);
  steps.forEach((step, index) => {
    const y = 567 - index * 36; p.circle(52, y, 11, index === 4 ? C.teal : C.blue);
    p.text(step[0], 45.5, y - 2.7, 6.5, { bold: true, color: C.white });
    p.text(step[1], 76, y + 3, 7.3, { bold: true, color: C.navy, tracking: 0.45 });
    p.text(step[2], 155, y + 3, 7.4, { color: C.muted });
  });

  p.sectionLabel('Verified controlled behavior', 32, 388, C.green);
  p.rect(32, 292, 258, 78, C.white, C.line, 0.7); p.rect(305, 292, 258, 78, C.white, C.line, 0.7);
  p.circle(52, 348, 7, C.redSoft); p.circle(52, 348, 3, C.red);
  p.text('ERROR MODE', 68, 345, 7.4, { bold: true, color: C.red, tracking: 0.5 });
  p.text('Deliberate HTTP 500', 48, 325, 11, { bold: true, color: C.navy });
  p.wrap('Selected /test mode confirmed as root cause; stopping controlled traffic restored service.', 48, 309, 220, 7.4, { color: C.muted, leading: 10 });
  p.circle(325, 348, 7, C.amberSoft); p.circle(325, 348, 3, C.amber);
  p.text('LATENCY MODE', 341, 345, 7.4, { bold: true, color: C.amber, tracking: 0.5 });
  p.text('Fixed 400 ms success', 321, 325, 11, { bold: true, color: C.navy });
  p.wrap('Validated separately from error mode without suppressing or bypassing the alert.', 321, 309, 220, 7.4, { color: C.muted, leading: 10 });

  p.sectionLabel('Evidence chain', 32, 262);
  const evidence = [
    { x: 32, w: 92, label: 'UTC SYMPTOM' }, { x: 138, w: 88, label: 'ALERT STATE' },
    { x: 240, w: 88, label: 'EXEMPLAR' }, { x: 342, w: 88, label: 'JAEGER' },
    { x: 444, w: 119, label: 'CLOUDWATCH ID' }
  ];
  evidence.forEach((item, index) => {
    p.rect(item.x, 224, item.w, 25, index % 2 ? C.tealSoft : C.blueSoft);
    p.text(item.label, item.x + 9, 233, 6.6, { bold: true, color: index % 2 ? C.teal : C.blue, tracking: 0.35 });
    if (index < evidence.length - 1) p.arrow(item.x + item.w + 3, 236.5, evidence[index + 1].x - 3, C.muted);
  });

  p.sectionLabel('Acceptance boundary', 32, 197);
  p.rect(32, 70, 531, 109, C.white, C.line, 0.7); p.rect(32, 70, 265.5, 109, C.greenSoft);
  p.text('PROVEN IN REPOSITORY', 48, 157, 7, { bold: true, color: C.green, tracking: 0.6 });
  p.wrap('HTTP server/client tracing; RED metrics and exemplars; Jaeger/Grafana provisioning; both 10-minute alerts; temporary phase routes removed.', 48, 138, 222, 7.5, { color: C.ink, leading: 11 });
  p.text('Durable demo surface', 48, 91, 7, { bold: true, color: C.green }); p.text('POST /test remains documented.', 143, 91, 7, { color: C.muted });
  p.text('VERIFIED IN DEPLOYMENT', 314, 157, 7, { bold: true, color: C.blue, tracking: 0.6 });
  p.wrap('Healthy Jaeger; populated panels; full alert lifecycle; trace links; exact CloudWatch correlation; versions; recovery and ordinary traces.', 314, 138, 223, 7.5, { color: C.ink, leading: 11 });
  p.text('Limits', 314, 91, 7, { bold: true, color: C.blue }); p.text('Non-durable Jaeger; 100% lab sampling; DB N/A.', 348, 91, 7, { color: C.muted });
  p.footer(2, 'SANITIZED EVIDENCE  /  evidence/mod10/');
  return p.commands.join('\n');
}

const streams = [pageOne(), pageTwo()];
const objects = [
  '<< /Type /Catalog /Pages 2 0 R /PageMode /UseNone >>',
  '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>',
  '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 7 0 R /F2 8 0 R >> >> /Contents 4 0 R >>',
  `<< /Length ${Buffer.byteLength(streams[0])} >>\nstream\n${streams[0]}\nendstream`,
  '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 7 0 R /F2 8 0 R >> >> /Contents 6 0 R >>',
  `<< /Length ${Buffer.byteLength(streams[1])} >>\nstream\n${streams[1]}\nendstream`,
  '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
  '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>',
  '<< /Title (Module 10 Observability and Security Report) /Author (AMALI TECH) /Subject (Advanced observability design and controlled acceptance) /Creator (Dependency-free Node.js PDF renderer) >>'
];
let pdf = '%PDF-1.4\n%\xE2\xE3\xCF\xD3\n'; const offsets = [0];
objects.forEach((object, index) => { offsets.push(Buffer.byteLength(pdf, 'binary')); pdf += `${index + 1} 0 obj\n${object}\nendobj\n`; });
const xref = Buffer.byteLength(pdf, 'binary');
pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
offsets.slice(1).forEach((offset) => { pdf += `${String(offset).padStart(10, '0')} 00000 n \n`; });
pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R /Info 9 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
fs.writeFileSync(output, Buffer.from(pdf, 'binary'));
console.log(`Rendered ${output} (${streams.length} pages)`);
