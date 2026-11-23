// Count client-log lines per category/pattern inside time windows.
// usage: node count-window.js <log> <label>=<HH:MM:SS>-<HH:MM:SS> ...
const fs = require('fs');
const lines = fs.readFileSync(process.argv[2], 'utf8').split(/\r?\n/);
const pats = {
  spawnProxy: /SpawnCccProxy: spawning/,
  lookBuild: /LoadLookFromArrays/,
  clothRebuild: /rebuilt cloth/,
  scaleReconcile: /reconciled actor/,
  proxyReady: /proxy ready to drive/,
  character: /\[character\]/,
  destroyed: /destroy|despawn|removed/i,
};
for (const arg of process.argv.slice(3)) {
  const [label, range] = arg.split('=');
  const [from, to] = range.split('-');
  const counts = Object.fromEntries(Object.keys(pats).map(k => [k, 0]));
  let total = 0;
  for (const l of lines) {
    const t = l.slice(12, 20); // "[YYYY-MM-DD HH:MM:SS.mmm]" -> HH:MM:SS
    if (t < from || t > to) continue;
    total++;
    for (const [k, re] of Object.entries(pats)) {
      const r = k === 'destroyed' ? /destroy|despawn|removed/i : re;
      if (r.test(l)) counts[k]++;
    }
  }
  console.log(label.padEnd(18), 'lines', String(total).padStart(6), JSON.stringify(counts));
}
