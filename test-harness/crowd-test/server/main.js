// crowd-test: spawn a repeatable crowd of characters around a player, to measure client FPS.
//
// A run: teleport the player to the Quidditch pitch, wait SETTLE_S, then step through the schedule
// (crowd size per phase, PHASE_S each), logging phase start/end with the client's frame-proxy readings.
// Modes:
//   walk  - every character walks a short back-and-forth path
//   heavy - every character holds a wand; every few seconds each one sprints/jogs to a random spot or
//           stops and plays a spell-cast animation, and casts fire a magic effect at it
//
// Server console commands (type into the server window):
//   crowdrun <walk|heavy> [n1,n2,...]   start a run for the first online player
//   crowdstop                           stop the run and remove the crowd
// Chat commands: /crowd <n> [walk|stand|heavy] [look|plain], /crowd 0, /crowdinfo

const HUMAN_ID = "GerboldOllivander"; // human id: "built on the same body as a player's"
const PLAIN_IDS = ["T3TownspersonMale1", "T3TownspersonFemale1"];
const RING0_CM = 300;      // first ring radius
const RING_STEP_CM = 170;  // distance between rings
const SLOT_CM = 160;       // spacing along a ring
const WALK_CM = 400;       // length of each back-and-forth walk
let SPREAD = 1;            // console: crowdspread <x>  (ring radius multiplier for the next spawn)
const MAX_CROWD = 250;

const SETTLE_S = 60;
const PHASE_S = 120;
const DEFAULT_SCHEDULE = [0, 25, 50, 100, 150, 200, 0];

// Open ground for the test: the Quidditch pitch POI (HW_QuidditchPitch, from Foundations'
// quidditch.config.js), which sits ~2 m above the deck; snapToGround drops the player onto it.
const PITCH = { x: 323482.0, y: -465966.0, z: -85353.9 };

// Spell-cast and wand clips from the game's own asset list (hmp-emotes emote_assets.json).
const A = (n) => `/Game/Animation/Human/${n}.${n}`;
const CAST_CLIPS = [
  A("Hu_BM_RF_Cast_Casual_Fwd_01_anm"),
  A("Hu_BM_RF_Cast_Casual_Fwd_02_anm"),
  A("Hu_BM_RF_Cast_Casual_Fwd_03_anm"),
  A("Hu_BM_RF_Cast_Casual_Fwd_04_anm"),
  A("Hu_BM_Spell_Flipendo_Fwd_anm"),
  A("Hu_BM_Spell_Revelio_anm"),
  A("Hu_BM_Spell_Oppugno_Loop_anm"),
  A("Hu_BM_RF_Idle2Cmbt_RF_Wand_Equip_Flourish_anm"),
];
const SIT_CLIPS = [
  "/Game/Animation/Human/Stations/Sitting/HU_STN_SIT_Bench_Idle_EatingApple_ANM.HU_STN_SIT_Bench_Idle_EatingApple_ANM",
  "/Game/Animation/Human/Stations/Sitting/HU_STN_SIT_Bench_Idle_Reading_ANM.HU_STN_SIT_Bench_Idle_Reading_ANM",
];
// Apple mesh from the docs' equipProp example (beasts-and-characters.md:138).
const APPLE = "/Game/Environment/BanditCamps/Bandit_Camp_Shared_Props/Food/SM_BCProps_Apple_A_2bite.SM_BCProps_Apple_A_2bite";
// Human character ids the CHRONIX server spawned (seen in its client log as "[character] proxy -> '<id>'").
const NAMED_IDS_ALL = ["AgnesCoffey", "AgnesScriven", "MirabelGarlick", "VictorRookwood", "ClaireBeaumont", "AugustusHill",
  "PercivalPippin", "GeorgeOsric", "CliffordCromwell", "EdgarAdley", "TimothyTeasdale", "FlorenceGreen", "AlbieWeekes",
  "ThomasBrown", "AesopSharp", "NiamhFitzgerald", "Sirona"];
let NAMED_IDS = null;
const PLAYERLIKE = ["players", "churn", "fxall", "labels"];
const HEAVY_TICK_MS = 500;      // driver tick
const HEAVY_ACT_MIN_MS = 3000;  // each character acts every 3-7 s
const HEAVY_ACT_MAX_MS = 7000;
const HEAVY_AREA_CM = 1800;     // run targets within this radius of the crowd centre

let crowd = [];        // { key, c, home, nextAt }
let crowdCentre = null;
let heavyTimer = null;
let magicFx = [];
let fxCounter = 0;
let stats = { runs: 0, casts: 0, fx: 0, actErrors: 0, firstActError: "" };

let autoTimer = null;
let autoRunning = false;
let runMode = "walk";
let runSchedule = DEFAULT_SCHEDULE;
let phaseLabel = "idle";
const samples = [];
const pendingTeleports = new Map();

function log(msg) {
  console.log(`[crowd-test] ${new Date().toISOString()} ${msg}`);
}

function stopHeavy() {
  if (heavyTimer) { clearInterval(heavyTimer); heavyTimer = null; }
}

let churnTimer = null;
let labelTimer = null;

function clearCrowd() {
  stopHeavy();
  if (churnTimer) { clearInterval(churnTimer); churnTimer = null; }
  if (labelTimer) { clearInterval(labelTimer); labelTimer = null; }
  let removed = 0;
  for (const m of crowd) {
    destroyExtras(m);
    try { if (Character.destroy(m.key)) removed++; } catch (e) { /* already gone */ }
  }
  crowd = [];
  return removed;
}

function ringPositions(origin, count) {
  const out = [];
  let ring = 0;
  while (out.length < count) {
    const r0 = RING0_CM + ring * RING_STEP_CM;
    const r = r0 * SPREAD;   // SPREAD > 1 keeps the same rings but spaces them out (wider, like an outdoor server)
    const slots = Math.max(6, Math.floor((2 * Math.PI * r0) / SLOT_CM));
    for (let s = 0; s < slots && out.length < count; s++) {
      const a = (2 * Math.PI * s) / slots + ring * 0.37;
      out.push({ x: origin.x + Math.cos(a) * r, y: origin.y + Math.sin(a) * r, z: origin.z, a, r });
    }
    ring++;
  }
  return out;
}

function loadMagicFx() {
  try {
    const all = Fx.catalog() || [];
    magicFx = all.filter(e => /magic/i.test(String(e.category || ""))).map(e => e.path).filter(Boolean);
    log(`fx catalog: ${all.length} entries, ${magicFx.length} magic` + (magicFx[0] ? ` (e.g. ${magicFx[0]})` : ""));
  } catch (e) {
    magicFx = [];
    log(`fx catalog failed: ${e && e.message ? e.message : e}`);
  }
}

function namedIds() {
  if (NAMED_IDS) return NAMED_IDS;
  NAMED_IDS = NAMED_IDS_ALL.filter(id => { try { return Character.isAllowed(id) && Character.isMovable(id); } catch (e) { return false; } });
  log(`named ids allowed: ${NAMED_IDS.length}/${NAMED_IDS_ALL.length} (${NAMED_IDS.join(",")})`);
  return NAMED_IDS;
}

// A player-like body: even slots wear the player's own look (modded outfits), odd slots a named
// character's own outfit; every one at a non-1 size, as CHRONIX players mostly are.
function bodyFor(i, look, variant) {
  const ids = namedIds();
  const scale = 0.85 + Math.random() * 0.25;
  if ((i + variant) % 2 === 0 && look) return { id: HUMAN_ID, extra: { look, scale } };
  if (ids.length === 0) return { id: HUMAN_ID, extra: look ? { look, scale } : { scale } };
  return { id: ids[(i * 7 + variant * 3) % ids.length], extra: { scale } };
}

function dressUp(m) {
  try { if (Math.random() < 0.7) m.c.setWand(true); } catch (e) { /* no wand socket */ }
  try { if (Math.random() < 0.15) m.c.equipProp(APPLE, { socket: "SKT_LeftHandSocket" }); } catch (e) { /* no socket */ }
}

function attachExtras(m, mode) {
  m.extras = m.extras || [];
  if (mode === "fxall" && magicFx.length > 0) {
    const p = m.home;
    const fx = Fx.create(`attfx-${m.key}-${fxCounter++}`, magicFx[fxCounter % magicFx.length], { x: p.x, y: p.y, z: p.z, drawDistance: 0 });
    if (fx) { fx.attachTo(m.c, { x: 0, y: 0, z: 60 }); m.extras.push(fx); }
  }
  if (mode === "labels") {
    for (let k = 0; k < 2; k++) {
      const lab = TextLabel.create(m.home.x, m.home.y, m.home.z, `${m.key} ${k}`);
      if (lab) { lab.attachTo(m.c, { x: 0, y: 0, z: 120 + k * 30 }); m.extras.push(lab); }
    }
  }
}

function destroyExtras(m) {
  for (const e of m.extras || []) { try { e.destroy(); } catch (err) { /* gone with its entity */ } }
  m.extras = [];
}

// Re-create one member with a different body (outfit change / respawn), keeping its slot.
function recreate(m, look, mode) {
  destroyExtras(m);
  m.variant = (m.variant || 0) + 1;
  const b = bodyFor(m.index, look, m.variant);
  const c = Character.create(m.key, b.id, Object.assign({ x: m.home.x, y: m.home.y, z: m.home.z, yaw: m.yaw }, b.extra));
  if (!c) return false;
  m.c = c;
  dressUp(m);
  attachExtras(m, mode);
  stats.recreates = (stats.recreates || 0) + 1;
  return true;
}

function heavyAct(m, now) {
  const roll = Math.random();
  if (m.playerlike && roll >= 0.8) {
    // Sit and eat or read: clips that carry props and sounds.
    m.c.playClip(SIT_CLIPS[Math.floor(Math.random() * SIT_CLIPS.length)], { loop: true });
    stats.sits = (stats.sits || 0) + 1;
    return;
  }
  if (roll < 0.55) {
    // Run somewhere: jog or sprint to a random point in the area.
    const ang = Math.random() * 2 * Math.PI;
    const dist = Math.random() * HEAVY_AREA_CM;
    const gait = Math.random() < 0.5 ? "sprint" : "jog";
    m.c.moveTo(crowdCentre.x + Math.cos(ang) * dist, crowdCentre.y + Math.sin(ang) * dist, crowdCentre.z, { gait });
    stats.runs++;
  } else {
    // Stop and cast: a cast clip, and a magic effect at the caster.
    const clip = CAST_CLIPS[Math.floor(Math.random() * CAST_CLIPS.length)];
    m.c.playClip(clip, { loop: false, hold: false });
    stats.casts++;
    if (magicFx.length > 0) {
      const p = m.c.position || m.home;
      const path = magicFx[Math.floor(Math.random() * magicFx.length)];
      Fx.create(`crowdfx-${fxCounter++}`, path, { x: p.x, y: p.y, z: p.z + 100, ttl: 3 });
      stats.fx++;
    }
  }
}

function startHeavy(playerlike) {
  stopHeavy();
  if (magicFx.length === 0) loadMagicFx();
  const now = Date.now();
  for (const m of crowd) {
    if (!playerlike) { try { m.c.setWand(true); } catch (e) { /* body without a wand socket */ } }
    m.nextAt = now + Math.random() * HEAVY_ACT_MAX_MS;
  }
  heavyTimer = setInterval(() => {
    const t = Date.now();
    for (const m of crowd) {
      if (t < m.nextAt) continue;
      m.nextAt = t + HEAVY_ACT_MIN_MS + Math.random() * (HEAVY_ACT_MAX_MS - HEAVY_ACT_MIN_MS);
      try { heavyAct(m, t); } catch (e) {
        stats.actErrors++;
        if (!stats.firstActError) { stats.firstActError = String(e && e.message ? e.message : e); log(`heavy action error: ${stats.firstActError}`); }
      }
    }
  }, HEAVY_TICK_MS);
}

// "scene": a live RP server as measured on CHRONIX (2026-11-23): the client held 60-71 remote players, most
// within 10 m (classroom / hall), with the rest of a 248/250 server farther away. SCENE_NEAR bodies in a
// room-sized disc doing room things, the remainder walking 30-100 m out; the server's own streaming decides
// how many of those reach the client.
const SCENE_NEAR = 65;
const SCENE_NEAR_CM = 1000;
const SCENE_FAR_MIN_CM = 3000;
const SCENE_FAR_MAX_CM = 10000;

function spawnScene(player, count, look, useLook) {
  const origin = player.position;
  const nNear = Math.min(SCENE_NEAR, count);
  let ok = 0, failed = 0, firstError = "";
  const roles = { idle: 0, sit: 0, pace: 0, cast: 0, far: 0 };
  for (let i = 0; i < count; i++) {
    const near = i < nNear;
    const ang = Math.random() * 2 * Math.PI;
    const dist = near ? 150 + Math.sqrt(Math.random()) * (SCENE_NEAR_CM - 150)
                      : SCENE_FAR_MIN_CM + Math.random() * (SCENE_FAR_MAX_CM - SCENE_FAR_MIN_CM);
    const p = { x: origin.x + Math.cos(ang) * dist, y: origin.y + Math.sin(ang) * dist, z: origin.z };
    const yaw = ((ang * 180) / Math.PI + 180) % 360;   // near ones face the player, like a class facing a teacher
    const key = `crowd-${i}`;
    try {
      const b = bodyFor(i, useLook ? look : null, 0);
      const c = Character.create(key, b.id, Object.assign({ x: p.x, y: p.y, z: p.z, yaw }, b.extra));
      if (!c) { failed++; continue; }
      const r = i % 20;
      const role = !near ? "far" : r < 10 ? "idle" : r < 14 ? "sit" : r < 17 ? "pace" : "cast";
      const m = { key, c, index: i, yaw, home: p, nextAt: Date.now() + 10000 + Math.random() * 15000, variant: 0, playerlike: true, extras: [], role };
      crowd.push(m);
      dressUp(m);
      roles[role]++;
      ok++;
      const movable = Character.isMovable(b.id);
      if (role === "sit") {
        c.playClip(SIT_CLIPS[i % SIT_CLIPS.length], { loop: true });
      } else if (role === "pace" && movable) {
        const a2 = Math.random() * 2 * Math.PI, d2 = 200 + Math.random() * 100;
        c.moveAlong([
          { x: p.x + Math.cos(a2) * d2, y: p.y + Math.sin(a2) * d2, z: p.z, wait: 8 + (i % 8) },
          { x: p.x, y: p.y, z: p.z, wait: 8 + ((i + 3) % 8) },
        ], { loop: "loop" });
      } else if (role === "far" && movable) {
        const a2 = Math.random() * 2 * Math.PI, d2 = 1000 + Math.random() * 1000;
        c.moveAlong([
          { x: p.x + Math.cos(a2) * d2, y: p.y + Math.sin(a2) * d2, z: p.z, wait: i % 4 },
          { x: p.x, y: p.y, z: p.z, wait: (i + 2) % 4 },
        ], { loop: "loop" });
      }
    } catch (e) {
      failed++;
      if (!firstError) firstError = String(e && e.message ? e.message : e);
    }
  }
  // Casters: a cast clip and a magic effect every 10-25 s.
  if (magicFx.length === 0) loadMagicFx();
  heavyTimer = setInterval(() => {
    const t = Date.now();
    for (const m of crowd) {
      if (m.role !== "cast" || t < m.nextAt) continue;
      m.nextAt = t + 10000 + Math.random() * 15000;
      try {
        m.c.playClip(CAST_CLIPS[Math.floor(Math.random() * CAST_CLIPS.length)], { loop: false, hold: false });
        stats.casts++;
        if (magicFx.length > 0) {
          const q = m.c.position || m.home;
          Fx.create(`crowdfx-${fxCounter++}`, magicFx[Math.floor(Math.random() * magicFx.length)], { x: q.x, y: q.y, z: q.z + 100, ttl: 3 });
          stats.fx++;
        }
      } catch (e) {
        stats.actErrors++;
        if (!stats.firstActError) { stats.firstActError = String(e && e.message ? e.message : e); log(`scene action error: ${stats.firstActError}`); }
      }
    }
  }, HEAVY_TICK_MS);
  log(`scene spawned ${ok}/${count}: idle ${roles.idle} sit ${roles.sit} pace ${roles.pace} cast ${roles.cast} far ${roles.far}` +
    (failed ? `, ${failed} failed: ${firstError}` : ""));
  return { ok, failed, useLook };
}

function spawnCrowd(player, count, mode, dress) {
  clearCrowd();
  if (count <= 0) return { ok: 0, failed: 0, useLook: false };
  const origin = player.position;
  crowdCentre = { x: origin.x, y: origin.y, z: origin.z };
  const look = dress === "look" ? player.getLook() : null;
  const useLook = !!(look && look.presets && Object.keys(look.presets).length > 0);
  if (mode === "scene") return spawnScene(player, count, look, useLook);
  let ok = 0;
  let failed = 0;
  let firstError = "";
  const spots = ringPositions(origin, count);
  const playerlike = PLAYERLIKE.includes(mode);
  if (playerlike && magicFx.length === 0) loadMagicFx();
  for (let i = 0; i < spots.length; i++) {
    const p = spots[i];
    const key = `crowd-${i}`;
    try {
      const yaw = ((p.a * 180) / Math.PI + 180) % 360;
      let id = useLook ? HUMAN_ID : PLAIN_IDS[i % PLAIN_IDS.length];
      const options = { x: p.x, y: p.y, z: p.z, yaw };
      if (playerlike) {
        const b = bodyFor(i, useLook ? look : null, 0);
        id = b.id;
        Object.assign(options, b.extra);
      } else if (mode === "walknamed") {
        // Same walk as "walk", but every body wears a named character's own (unmodded) outfit.
        const ids = namedIds();
        if (ids.length > 0) id = ids[i % ids.length];
      } else if (useLook) {
        options.look = look;
      }
      const c = Character.create(key, id, options);
      if (!c) { failed++; continue; }
      const m = { key, c, index: i, yaw, home: { x: p.x, y: p.y, z: p.z }, nextAt: 0, variant: 0, playerlike, extras: [] };
      crowd.push(m);
      if (playerlike) { dressUp(m); attachExtras(m, mode); }
      ok++;
      if ((mode === "walk" || mode === "walknamed") && Character.isMovable(id)) {
        const tx = -Math.sin(p.a) * WALK_CM;
        const ty = Math.cos(p.a) * WALK_CM;
        c.moveAlong([
          { x: p.x + tx, y: p.y + ty, z: p.z, wait: i % 3 },
          { x: p.x, y: p.y, z: p.z, wait: (i + 1) % 3 },
        ], { loop: "loop" });
      }
    } catch (e) {
      failed++;
      if (!firstError) firstError = String(e && e.message ? e.message : e);
    }
  }
  if ((mode === "heavy" || playerlike) && ok > 0) startHeavy(playerlike);
  if (mode === "churn" && ok > 0) {
    // Outfit changes: each member re-created with another body about every 20 s, plus one
    // all-at-once burst 60 s into the phase (the 71-per-second spawn peaks seen on CHRONIX).
    const perSec = Math.max(1, Math.round(crowd.length / 20));
    let cursor = 0;
    const started = Date.now();
    let burstDone = false;
    churnTimer = setInterval(() => {
      try {
        if (!burstDone && Date.now() - started >= 60000) {
          burstDone = true;
          for (const m of crowd) recreate(m, useLook ? look : null, mode);
          log(`churn burst: re-created ${crowd.length}`);
          return;
        }
        for (let k = 0; k < perSec && crowd.length > 0; k++) { recreate(crowd[cursor % crowd.length], useLook ? look : null, mode); cursor++; }
      } catch (e) {
        stats.actErrors++;
        if (!stats.firstActError) { stats.firstActError = String(e && e.message ? e.message : e); log(`churn error: ${stats.firstActError}`); }
      }
    }, 1000);
  }
  if (mode === "labels" && ok > 0) {
    let tick = 0;
    labelTimer = setInterval(() => {
      tick++;
      for (const m of crowd) for (const e of m.extras) { try { e.setText(`${m.key} ${tick}`); } catch (err) { /* gone */ } }
    }, 1000);
  }
  log(`spawned ${ok}/${count} (${mode}, ${useLook ? "player look" : "plain bodies"})` +
    (failed ? `, ${failed} failed: ${firstError}` : ""));
  return { ok, failed, useLook };
}

function summarizePhase() {
  if (samples.length === 0) return "no client samples";
  const t = samples.map(s => s.ticksPerSec).sort((a, b) => a - b);
  const g = samples.map(s => s.maxGapMs).sort((a, b) => a - b);
  const mean = t.reduce((a, b) => a + b, 0) / t.length;
  const pct = (arr, q) => arr[Math.min(arr.length - 1, Math.floor(q * arr.length))];
  return `client timer ticks/s mean ${mean.toFixed(1)} p10 ${pct(t, 0.1)} p50 ${pct(t, 0.5)} | worst gap ms p50 ${pct(g, 0.5)} p90 ${pct(g, 0.9)} max ${g[g.length - 1]} (n=${samples.length})` +
    (runMode !== "walk" ? ` | ${runMode} runs ${stats.runs} casts ${stats.casts} fx ${stats.fx} sits ${stats.sits || 0} recreates ${stats.recreates || 0} errors ${stats.actErrors}` +
      (stats.firstActError ? ` (first: ${stats.firstActError})` : "") : "");
}

function runPhases(player) {
  if (autoTimer) clearTimeout(autoTimer);
  autoRunning = true;
  let idx = -1;
  const next = () => {
    if (idx >= 0) log(`PHASE END ${phaseLabel}: ${summarizePhase()}`);
    idx++;
    if (idx >= runSchedule.length || !PlayerManager.getAll().some(p => p.id === player.id)) {
      clearCrowd();
      autoRunning = false;
      phaseLabel = "done";
      log("SCHEDULE DONE");
      return;
    }
    const n = runSchedule[idx];
    samples.length = 0;
    stats = { runs: 0, casts: 0, fx: 0, actErrors: 0, firstActError: "" };
    const res = spawnCrowd(player, n, runMode, "look");
    phaseLabel = `${idx}:${runMode}:crowd=${n}(spawned ${res.ok})`;
    log(`PHASE START ${phaseLabel}`);
    autoTimer = setTimeout(next, PHASE_S * 1000);
  };
  log(`schedule armed: mode ${runMode}, settle ${SETTLE_S}s, then ${runSchedule.join(",")} x ${PHASE_S}s`);
  phaseLabel = "settle";
  autoTimer = setTimeout(next, SETTLE_S * 1000);
}

function startRun(player, mode, schedule) {
  if (autoRunning) { log("a run is already going; crowdstop first"); return; }
  runMode = mode || "walk";
  runSchedule = schedule && schedule.length ? schedule : DEFAULT_SCHEDULE;
  autoRunning = true;
  phaseLabel = "teleport";
  const requestId = player.teleport(PITCH.x, PITCH.y, PITCH.z, { yaw: 0, snapToGround: true });
  log(`run requested (${runMode}); teleport to pitch id ${requestId}`);
  if (requestId > 0) pendingTeleports.set(requestId, player.id);
  setTimeout(() => {
    if (phaseLabel === "teleport") { log("teleport completion not seen in 30s; starting anyway"); runPhases(player); }
  }, 30000);
}

function stopRun() {
  if (autoTimer) { clearTimeout(autoTimer); autoTimer = null; }
  const removed = clearCrowd();
  autoRunning = false;
  phaseLabel = "stopped";
  log(`run stopped, removed ${removed}`);
}

Events.on("playerTeleportComplete", (player, requestId, status) => {
  if (!pendingTeleports.has(requestId)) return;
  pendingTeleports.delete(requestId);
  log(`teleport complete: status ${status}`);
  if (phaseLabel === "teleport") runPhases(player);
});

Events.on("loadingFinished", (player) => {
  log(`loadingFinished for ${player.nickname} (id ${player.id}) at ${JSON.stringify(player.position)}`);
});

// Command file: each line of <server>/crowd-cmd.txt ("crowdrun walk 100,100") runs like a console command,
// then the file is deleted. Lets a test driver send commands without typing into the console window.
let fsMod = null;
try { fsMod = require("fs"); } catch (e) { log("command file disabled: " + e); }
const CMD_FILE = "crowd-cmd.txt";
if (fsMod) {
  setInterval(() => {
    try {
      if (!fsMod.existsSync(CMD_FILE)) return;
      const text = fsMod.readFileSync(CMD_FILE, "utf8");
      fsMod.unlinkSync(CMD_FILE);
      for (const line of text.split(/\r?\n/)) {
        const parts = line.trim().split(/\s+/).filter(Boolean);
        if (parts.length === 0) continue;
        log("command file: " + parts.join(" "));
        handleCommand(parts[0], parts.slice(1));
      }
    } catch (e) { log("command file error: " + e); }
  }, 1000);
  log("command file enabled: " + CMD_FILE + " (cwd " + process.cwd() + ")");
}

Events.on("consoleCommand", (command, args) => handleCommand(command, args));

function handleCommand(command, args) {
  const cmd = String(command).toLowerCase();
  if (cmd === "crowdstop") { stopRun(); return; }
  if (cmd === "crowdspread") {
    const v = Number(args && args[0]);
    if (v > 0 && v <= 10) SPREAD = v;
    log("spread now " + SPREAD);
    return;
  }
  if (cmd !== "crowdrun") return;
  const requested = String((args && args[0]) || "walk").toLowerCase();
  const mode = ["walk", "walknamed", "stand", "heavy", "scene", ...PLAYERLIKE].includes(requested) ? requested : "walk";
  const schedule = args && args[1] ? String(args[1]).split(",").map(Number).filter(n => Number.isFinite(n) && n >= 0 && n <= MAX_CROWD) : null;
  const online = PlayerManager.getAll();
  if (online.length === 0) { log("crowdrun: nobody online"); return; }
  startRun(online[0], mode, schedule);
}

Events.onClient("crowdtest:frame", (player, payload) => {
  if (!payload || typeof payload.ticksPerSec !== "number") return;
  samples.push({ ticksPerSec: payload.ticksPerSec, maxGapMs: payload.maxGapMs });
  log(`sample ${phaseLabel} ticks/s ${payload.ticksPerSec} maxGapMs ${payload.maxGapMs}`);
});

Events.on("chatCommand", (player, message, command, args) => {
  const cmd = String(command).toLowerCase();
  if (cmd === "crowdinfo") {
    const msg = `crowd ${crowd.length}, live characters ${CharacterManager.getAll().length}, phase ${phaseLabel}`;
    log(msg);
    player.sendChat(`[crowd-test] ${msg}`);
    return;
  }
  if (cmd !== "crowd") return;
  const n = Math.max(0, Math.min(MAX_CROWD, Number(args[0]) || 0));
  const m = String(args[1] || "walk").toLowerCase();
  const mode = m === "stand" ? "stand" : m === "heavy" ? "heavy" : "walk";
  const dress = String(args[2] || "look").toLowerCase() === "plain" ? "plain" : "look";
  if (n === 0) { const removed = clearCrowd(); player.sendChat(`[crowd-test] removed ${removed}`); return; }
  const res = spawnCrowd(player, n, mode, dress);
  player.sendChat(`[crowd-test] spawned ${res.ok}/${n}`);
});

log("ready (v0.4): console 'crowdrun <walk|heavy> [n,n,...]', 'crowdstop'; chat /crowd, /crowdinfo");
