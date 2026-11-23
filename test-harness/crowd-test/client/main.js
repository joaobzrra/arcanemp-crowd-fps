// crowd-test client: a frame-rate proxy. A 1 ms interval timer fires at most once per pass of the
// client script loop; if that loop is pumped once per game frame, ticks per second tracks FPS and the
// longest gap between ticks tracks the worst frame time. Reported to the server every 5 seconds.

let ticks = 0;
let last = Date.now();
let maxGap = 0;
let windowStart = Date.now();

setInterval(() => {
  const now = Date.now();
  const gap = now - last;
  if (gap > maxGap) maxGap = gap;
  last = now;
  ticks++;
  if (now - windowStart >= 5000) {
    const seconds = (now - windowStart) / 1000;
    Events.emitServer("crowdtest:frame", { ticksPerSec: Math.round(ticks / seconds), maxGapMs: maxGap });
    ticks = 0;
    maxGap = 0;
    windowStart = now;
  }
}, 1);
