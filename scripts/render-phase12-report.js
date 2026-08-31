#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const PDFDocument = require('pdfkit');

const out = path.resolve(__dirname, '../docs/observability-security-report.pdf');
const doc = new PDFDocument({ size: 'A4', margin: 0, info: { Title: 'Observability and security report', Author: 'Project 6 lab' } });
const W = 595.28, L = 48, CW = W - 96;
const c = { ink: '#172033', muted: '#5f6b7a', blue: '#2463a6', paleBlue: '#eaf3fb', green: '#1f7a4d', paleGreen: '#e9f6ee', orange: '#bc6500', paleOrange: '#fff3e2', line: '#d7e0ea', white: '#ffffff', slate: '#eff3f7' };
doc.pipe(fs.createWriteStream(out));
function box(x, y, w, h, color, radius) { doc.save().fillColor(color); radius ? doc.roundedRect(x, y, w, h, radius).fill() : doc.rect(x, y, w, h).fill(); doc.restore(); }
function outline(x, y, w, h, color, radius) { doc.save().lineWidth(1).strokeColor(color); radius ? doc.roundedRect(x, y, w, h, radius).stroke() : doc.rect(x, y, w, h).stroke(); doc.restore(); }
function t(value, x, y, o) { const a = o || {}; doc.font(a.bold ? 'Helvetica-Bold' : 'Helvetica').fontSize(a.size || 9).fillColor(a.color || c.ink).lineGap(a.gap || 1).text(value, x, y, { width: a.width || CW, align: a.align || 'left' }); }
function header(kicker, title, subtitle, page) {
  box(0, 0, W, 104, c.ink); t(kicker.toUpperCase(), L, 25, { size: 8, color: '#a9d2f5', bold: true });
  t(title, L, 41, { size: 23, color: c.white, bold: true }); t(subtitle, L, 73, { size: 9.2, color: '#d9e6f2' });
  t('PROJECT 6  ·  ' + page + ' / 2', L, 25, { size: 8, color: '#a9d2f5', bold: true, align: 'right' });
}
function section(label, y) { t(label.toUpperCase(), L, y, { size: 8, color: c.blue, bold: true }); box(L, y + 14, CW, 1, c.line); }
function card(x, y, w, h, label, value, detail, accent, pale) {
  box(x, y, w, h, c.white, 7); outline(x, y, w, h, c.line, 7); box(x, y, 5, h, accent, 7); box(x + w - 28, y + 13, 15, 15, pale, 7);
  t(label.toUpperCase(), x + 17, y + 14, { size: 7.4, color: accent, bold: true, width: w - 32 });
  t(value, x + 17, y + 29, { size: 16, bold: true, width: w - 32 });
  t(detail, x + 17, y + 53, { size: 7.8, color: c.muted, width: w - 32 });
}
function footer(page) {
  box(L, 790, CW, 1, c.line); t('Controlled traffic and the GuardDuty sample are labeled test evidence—not production incidents.', L, 802, { size: 7.4, color: c.muted, width: 400 });
  t('Project 6 · ' + page + ' of 2', L, 802, { size: 7.4, color: c.muted, align: 'right' });
}
function node(x, label, detail, color) {
  box(x, 261, 82, 55, c.white, 6); outline(x, 261, 82, 55, color, 6);
  t(label, x + 7, 271, { size: 7.7, color, bold: true, width: 68, align: 'center' });
  t(detail, x + 7, 287, { size: 6.8, color: c.muted, width: 68, align: 'center' });
}
function arrow(x) { doc.save().strokeColor('#93a6b8').lineWidth(1.1).moveTo(x, 289).lineTo(x + 16, 289).stroke(); doc.fillColor('#93a6b8').moveTo(x + 16, 286).lineTo(x + 22, 289).lineTo(x + 16, 292).fill().restore(); }

header('Observability & security', 'A defensible delivery path', 'Immutable deployment, private telemetry, and evidence-led operations', 1);
card(L, 124, 175, 84, 'Deployment', 'Immutable', 'GHCR digest deployed through strict SSH with candidate validation and rollback retention.', c.blue, c.paleBlue);
card(L + 187, 124, 175, 84, 'Monitoring', 'Private', 'Prometheus and Node Exporter stay off the public network; Grafana HTTPS is admin-restricted.', c.green, c.paleGreen);
card(L + 374, 124, 175, 84, 'Verification', 'Controlled', '>5% 5xx test proved Pending → Firing → Resolved, then restored normal service.', c.orange, c.paleOrange);
section('Architecture at a glance', 232);
node(L, 'GitHub + GHCR', 'push webhook\nimmutable digest', c.ink); node(L + 103, 'Jenkins', 'test · Trivy\ndeploy + rollback', c.blue);
node(L + 206, 'Application', 'HTTP :80\nmetrics :9464', c.green); node(L + 309, 'Prometheus', 'private scrape\n15s evaluation', '#b64b1f'); node(L + 412, 'Grafana', 'HTTPS /32\nSlack alerting', c.orange);
[L + 82, L + 185, L + 288, L + 391].forEach(arrow);
t('Application/Jenkins VPC 10.70.0.0/16', L, 330, { size: 7.6, color: c.muted, width: 280 });
t('Private VPC peering → Monitoring VPC 10.80.0.0/16', L, 330, { size: 7.6, color: c.muted, align: 'right' });
section('Controls that matter', 365);
t('Delivery safeguards', L, 392, { size: 10.5, bold: true, width: 245 });
t('Jenkins runs syntax/Jest/JUnit and repository/image Trivy gates before push. The application runs as UID/GID 10001 with a read-only filesystem, dropped capabilities, no-new-privileges, resource limits, and no Docker socket.', L, 411, { size: 8.55, color: c.muted, width: 245, gap: 2 });
t('Telemetry and secrets', L + 286, 392, { size: 10.5, bold: true, width: 261 });
t('Only Grafana is exposed. Application metrics and both Node Exporters use private peering. Slack and Cloudflare credentials are fetched at runtime from scoped Secrets Manager entries—not from Git, Terraform state, logs, or evidence.', L + 286, 411, { size: 8.55, color: c.muted, width: 261, gap: 2 });
box(L, 521, CW, 160, c.slate, 8);
t('SIGNALS AND ALERT POLICY', L + 18, 540, { size: 8, color: c.blue, bold: true, width: CW - 36 });
t('The provisioned dashboard tracks request rate, p95 latency, HTTP 5xx percentage, CPU, memory, disk, and scrape health.', L + 18, 560, { size: 10.2, bold: true, width: CW - 36 });
t('Prometheus evaluates every 15 seconds. JenkinsWebappHighErrorRate requires both a 5xx rate above 5% for five minutes and at least 20 requests in that five-minute window. The traffic guard prevents a tiny sample from creating noise.', L + 18, 593, { size: 8.75, color: c.muted, width: CW - 36, gap: 2 });
t('No raw URLs, request bodies, identities, tokens, or query strings are used as metric labels.', L + 18, 646, { size: 8.25, color: c.green, bold: true, width: CW - 36 });
footer(1);

doc.addPage();
header('Executed evidence', 'Recovery was observed end to end', 'The test validates alerting and logging without presenting controlled traffic as an incident', 2);
section('Controlled alert lifecycle · 2026-08-30 UTC', 128);
const timeline = [['14:04:28', 'Traffic started', 'Normal and deliberate fault requests began every five seconds.'], ['14:04:55', 'Pending', 'JenkinsWebappHighErrorRate entered Pending.'], ['14:10:48', 'Firing', 'The threshold remained true for the required five minutes.'], ['14:11:00', 'Traffic stopped', 'No further controlled requests were generated.'], ['14:12:14', 'Fault disabled', 'Controller disabled; fault route returned HTTP 404.'], ['14:15:52', 'Resolved', 'Prometheus returned no active high-error alert.']];
timeline.forEach((item, i) => { const y = 162 + (i * 31); box(L, y + 2, 8, 8, item[1] === 'Firing' ? c.orange : c.green, 4); t(item[0], L + 22, y, { size: 8.3, bold: true, width: 55 }); t(item[1], L + 86, y, { size: 8.4, color: c.blue, bold: true, width: 102 }); t(item[2], L + 190, y, { size: 8.35, color: c.muted, width: 357 }); if (i < 5) box(L + 3.5, y + 13, 1, 17, c.line); });
section('What the verification proves', 367);
card(L, 394, 265, 116, 'Recovery state', '4 / 4 UP', 'Application, application-node, monitoring-node, and Prometheus were UP after restoration. The normal container was healthy, non-root, read-only, and fault injection was absent.', c.green, c.paleGreen);
card(L + 282, 394, 265, 116, 'Log correlation', '156 events', 'CloudWatch Logs Insights matched 156 controlled application 500/error events from 14:04:28.862 to 14:10:55.089 UTC, bracketing the traffic window.', c.blue, c.paleBlue);
section('Audit posture, limitations, and cleanup', 538);
t('CloudTrail and GuardDuty', L, 565, { size: 10.2, bold: true, width: 245 });
t('The dedicated archive has multi-Region management events, log-file validation, KMS encryption, blocked public access, versioning, and 30/90/365-day lifecycle controls. GuardDuty is enabled; the saved finding is AWS-generated synthetic evidence.', L, 584, { size: 8.45, color: c.muted, width: 245, gap: 2 });
t('Limits and teardown boundary', L + 286, 565, { size: 10.2, bold: true, width: 261 });
t('Monitoring runs on a cost-sensitive t3.micro. Official stable Grafana, Node Exporter, and Nginx images retain a documented lab exception for fixable Trivy HIGH findings; no CRITICAL finding is accepted. Preserve evidence, refresh ownership, then apply only an explicitly approved destroy plan. Shared resources are excluded.', L + 286, 584, { size: 8.45, color: c.muted, width: 261, gap: 2 });
box(L, 690, CW, 68, c.paleBlue, 8);
t('EVIDENCE INDEX', L + 17, 706, { size: 7.8, color: c.blue, bold: true, width: CW - 34 });
t('Phase 11 live verification · Phase 6 CloudTrail verification · Phase 7 GuardDuty synthetic sample · evidence/README.md', L + 17, 726, { size: 8.3, width: CW - 34 });
footer(2);
doc.end();
