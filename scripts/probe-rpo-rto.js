#!/usr/bin/env node
/**
 * =============================================================================
 * Empirical RTO & RPO Continuous Write Probe (Prompt 14 & Prompt 21)
 * =============================================================================
 * Sends monotonic sequence writes (POST /notes, seq_no = 1, 2, 3...) at a
 * configurable interval (default 500ms = 2 writes/sec) while polling primary
 * and secondary endpoints (or a unified failover endpoint).
 *
 * Automatically records:
 *   - T0 (first write failure in primary region us-east-1)
 *   - Last acknowledged seq_no & timestamp in us-east-1 before T0
 *   - T4 (first successful write in secondary region ap-south-1)
 *   - Maximum replicated seq_no present in ap-south-1 prior to new writes
 *   - Empirical RTO (ms & seconds) = T4 - T0
 *   - Empirical RPO (missing acknowledged writes & lag window in ms)
 *
 * Usage:
 *   node scripts/probe-rpo-rto.js \
 *     --primary http://<use1-alb-dns> \
 *     --secondary http://<aps1-alb-dns> \
 *     --trial 1 \
 *     --output evidence/trial-1.json
 */
'use strict';

const fs = require('node:fs');
const path = require('node:path');

function parseArgs(argv) {
  const args = {
    primary: process.env.PRIMARY_ALB_URL || 'http://localhost:3000',
    secondary: process.env.SECONDARY_ALB_URL || '',
    intervalMs: 500,
    maxRequests: 600,
    trial: 1,
    simulateDrill: false,
    output: ''
  };

  for (let i = 2; i < argv.length; i++) {
    const key = argv[i];
    const val = argv[i + 1];
    if (key === '--primary' && val) { args.primary = val.replace(/\/$/, ''); i++; }
    else if (key === '--secondary' && val) { args.secondary = val.replace(/\/$/, ''); i++; }
    else if (key === '--interval-ms' && val) { args.intervalMs = Number(val); i++; }
    else if (key === '--max-requests' && val) { args.maxRequests = Number(val); i++; }
    else if (key === '--trial' && val) { args.trial = Number(val); i++; }
    else if (key === '--output' && val) { args.output = val; i++; }
    else if (key === '--simulate-drill') { args.simulateDrill = true; }
  }
  return args;
}

async function httpJson(url, options = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), options.timeoutMs || 2000);
  const start = Date.now();
  try {
    const res = await fetch(url, {
      method: options.method || 'GET',
      headers: {
        'Content-Type': 'application/json',
        ...(options.headers || {})
      },
      body: options.body ? JSON.stringify(options.body) : undefined,
      signal: controller.signal
    });
    const text = await res.text();
    let json = null;
    try { json = JSON.parse(text); } catch { json = { raw: text }; }
    return {
      ok: res.ok,
      status: res.status,
      region: res.headers.get('x-served-by-region') || json?.written_region || json?.region || 'unknown',
      latencyMs: Date.now() - start,
      body: json
    };
  } catch (err) {
    return {
      ok: false,
      status: 0,
      region: 'unreachable',
      latencyMs: Date.now() - start,
      error: err.message
    };
  } finally {
    clearTimeout(timeout);
  }
}

async function runProbe() {
  const args = parseArgs(process.argv);
  const timeline = [];
  let seqNo = 1;
  let lastPrimaryAckSeq = 0;
  let lastPrimaryAckAt = null;
  let t0FailureStart = null;
  let t4RecoveryEnd = null;
  let prePromotionMaxSeqInSecondary = null;
  let activeTarget = args.primary;
  let failedOverToSecondary = false;

  console.log(`=== Starting Multi-Region HA RTO/RPO Write Probe (Trial #${args.trial}) ===`);
  console.log(`Primary Endpoint:   ${args.primary}`);
  console.log(`Secondary Endpoint: ${args.secondary || '(same/DNS failover)'}`);
  console.log(`Write Rate:         1 write every ${args.intervalMs}ms`);
  console.log('-------------------------------------------------------------------------');

  for (let step = 1; step <= args.maxRequests; step++) {
    const sentAt = new Date().toISOString();
    const res = await httpJson(`${activeTarget}/notes`, {
      method: 'POST',
      body: {
        seq_no: seqNo,
        title: `Trial-${args.trial}-Seq-${seqNo}`,
        content: `RPO tracking probe write #${seqNo} sent at ${sentAt}`,
        client_sent_at: sentAt
      }
    });

    const event = {
      step,
      seq_no: seqNo,
      target: activeTarget,
      timestamp: sentAt,
      status: res.status,
      served_by_region: res.region,
      latency_ms: res.latencyMs
    };
    timeline.push(event);

    if (res.ok && !failedOverToSecondary && res.region === 'us-east-1') {
      lastPrimaryAckSeq = seqNo;
      lastPrimaryAckAt = sentAt;
      console.log(`[${sentAt}] OK (Primary ${res.region}) seq_no=${seqNo} latency=${res.latencyMs}ms`);
      seqNo++;
    } else if (!res.ok) {
      if (!t0FailureStart) {
        t0FailureStart = sentAt;
        console.log(`\n>>> [T0 FAULT DETECTED at ${t0FailureStart}] Primary write failed (status=${res.status}). Last acked seq_no=${lastPrimaryAckSeq} <<<\n`);
      } else {
        console.log(`[${sentAt}] OUTAGE IN PROGRESS (status=${res.status}, target=${activeTarget}, elapsed=${((Date.now() - Date.parse(t0FailureStart)) / 1000).toFixed(1)}s)`);
      }

      // If secondary URL is provided, probe secondary GET /notes to check max replicated seq_no and try writing to secondary
      if (args.secondary) {
        const secNotes = await httpJson(`${args.secondary}/notes?limit=1`);
        if (secNotes.ok && prePromotionMaxSeqInSecondary === null && secNotes.body?.stats) {
          prePromotionMaxSeqInSecondary = Number(secNotes.body.stats.max_seq_no);
        }
        const secHealth = await httpJson(`${args.secondary}/health/deep`);
        if (secHealth.ok && secHealth.body?.db_role === 'writer') {
          console.log(`>>> Secondary (${args.secondary}) reports db_role="writer"! Switching probe target to secondary <<<`);
          activeTarget = args.secondary;
        }
      }
    } else if (res.ok && (activeTarget === args.secondary || res.region === 'ap-south-1')) {
      if (!t4RecoveryEnd) {
        t4RecoveryEnd = new Date().toISOString();
        failedOverToSecondary = true;
        console.log(`\n>>> [T4 RECOVERY CONFIRMED at ${t4RecoveryEnd}] First successful write in ${res.region} (seq_no=${seqNo}, latency=${res.latencyMs}ms) <<<\n`);
        seqNo++;
        // Record 3 more post-recovery writes and exit cleanly
        if (t0FailureStart) {
          break;
        }
      }
    }

    await new Promise((r) => setTimeout(r, args.intervalMs));
  }

  const rtoMs = (t0FailureStart && t4RecoveryEnd)
    ? (Date.parse(t4RecoveryEnd) - Date.parse(t0FailureStart))
    : null;
  const recoveredSeq = prePromotionMaxSeqInSecondary !== null
    ? prePromotionMaxSeqInSecondary
    : lastPrimaryAckSeq;
  const lostWrites = Math.max(0, lastPrimaryAckSeq - recoveredSeq);

  const report = {
    trial: args.trial,
    primary_endpoint: args.primary,
    secondary_endpoint: args.secondary,
    timestamps: {
      last_primary_ack_utc: lastPrimaryAckAt,
      t0_fault_onset_utc: t0FailureStart,
      t4_secondary_recovered_utc: t4RecoveryEnd
    },
    metrics: {
      rto_ms: rtoMs,
      rto_seconds: rtoMs !== null ? Number((rtoMs / 1000).toFixed(2)) : null,
      last_primary_acknowledged_seq_no: lastPrimaryAckSeq,
      secondary_recovered_max_seq_no: recoveredSeq,
      rpo_lost_writes_count: lostWrites,
      rpo_estimated_window_ms: lostWrites * args.intervalMs
    },
    total_probe_events: timeline.length
  };

  console.log('\n================ EMPIRICAL RTO / RPO SUMMARY ================');
  console.log(JSON.stringify(report, null, 2));
  console.log('=============================================================\n');

  if (args.output) {
    const outPath = path.resolve(args.output);
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    fs.writeFileSync(outPath, JSON.stringify({ report, timeline }, null, 2));
    console.log(`Saved raw trial evidence to: ${outPath}`);
  }
}

runProbe().catch((err) => {
  console.error('Probe failed:', err);
  process.exit(1);
});
