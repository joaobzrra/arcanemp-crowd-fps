// Summarize a crowd-monitor samples.csv per phase: mean busiest-thread %, 2nd/3rd thread %, process CPU %, GPU %, GPU W.
const fs = require('fs');
const rows = fs.readFileSync(process.argv[2], 'utf8').replace(/^﻿/, '').trim().split(/\r?\n/).map(l => l.split(','));
const head = rows.shift().map(h => h.replace(/^﻿/, ''));
const ix = n => head.indexOf(n);
const groups = new Map();
for (const r of rows) {
  const phase = r[ix('phase')] || '';
  const m = phase.match(/PHASE START (\S+)/);
  if (!m) continue;
  const key = m[1];
  if (!groups.has(key)) groups.set(key, []);
  groups.get(key).push(r);
}
const mean = (arr, col) => {
  const v = arr.map(r => Number(r[ix(col)])).filter(Number.isFinite);
  return v.length ? (v.reduce((a, b) => a + b, 0) / v.length) : NaN;
};
console.log('phase'.padEnd(34), 'n', 't1%', 't2%', 't3%', 'procCPU%', 'gpu%', 'gpuW', 'privGB');
for (const [k, arr] of groups) {
  // Skip the first 15 s of each phase (spawn burst) for steady-state numbers.
  const steady = arr.slice(3);
  console.log(k.padEnd(34), String(steady.length).padStart(2),
    mean(steady, 't1_pct').toFixed(0), mean(steady, 't2_pct').toFixed(0), mean(steady, 't3_pct').toFixed(0),
    mean(steady, 'proc_cpu_pct').toFixed(0), mean(steady, 'gpu_pct').toFixed(0), mean(steady, 'gpu_w').toFixed(0),
    mean(steady, 'private_gb').toFixed(2));
}
