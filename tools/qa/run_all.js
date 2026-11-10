#!/usr/bin/env node
// Финальная QA-батарея «Моркхейма». Один вход: node tools/qa/run_all.js
//
// Что делает:
//  1. Распаковывает HEAD (`git archive` → bsdtar) в изолированный стенд:
//     tools/appdata_qa/stage/pixel-rpg (main read-only, worktree не читается;
//     --stage=robocopy — легаси-копия рабочего дерева).
//  2. Кладёт поверх стенды из tools/qa/stand/ (.gd/.tscn в репозитории).
//  3. Один --import, затем каждый стенд отдельным headless-процессом Godot
//     (--fixed-fps 60), APPDATA/LOCALAPPDATA изолированы в tools/appdata_qa.
//  4. Парсит строки результатов стендов, печатает сводку: стенд/pass/fail/exit/вердикт.
//
// Запуск:  node tools/qa/run_all.js [--only=mb_1,qa_ng] [--skip-import] [--list] [--timeout=300]
// Выход:   0 — все GREEN; 1 — есть RED/NO_PARSE/ERROR.
//
// Примечание про окружение: в песочнице DSH процессы не открывают именованные каналы,
// поэтому Godot запускается через cmd /c "... > лог 2>&1" c stdio:'ignore' (без пайпов),
// а результат читается из лог-файла.
'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

// ── поиск корня воркспейса: предок с pixel-rpg/project.godot и tools/godot ──
function findRoot() {
  let p = __dirname;
  for (let i = 0; i < 8; i++) {
    if (fs.existsSync(path.join(p, 'pixel-rpg', 'project.godot')) &&
        fs.existsSync(path.join(p, 'tools', 'godot'))) return p;
    const up = path.dirname(p);
    if (up === p) break;
    p = up;
  }
  throw new Error('workspace root not found (pixel-rpg/project.godot + tools/godot)');
}
const ROOT = findRoot();
const QA = __dirname; // манифест и stand/ лежат рядом со скриптом (tools/qa)
const STAND = path.join(QA, 'stand');
const ISO = path.join(ROOT, 'tools', 'appdata_qa');
const STAGE = path.join(ISO, 'stage', 'pixel-rpg');
const LOGS = path.join(ISO, 'logs');
const USERDATA = path.join(ISO, 'app', 'Godot', 'app_userdata');
const GAME = path.join(ROOT, 'pixel-rpg');

function godotExe() {
  const d = path.join(ROOT, 'tools', 'godot');
  const f = fs.readdirSync(d).find((x) => /console\.exe$/i.test(x) && /^godot/i.test(x));
  if (!f) throw new Error('godot console exe not found in tools/godot');
  return path.join(d, f);
}
const GODOT = godotExe();
const ISO_ENV = Object.assign({}, process.env, {
  APPDATA: path.join(ISO, 'app'),
  LOCALAPPDATA: path.join(ISO, 'local'),
});

const argv = process.argv.slice(2);
const opt = (n, d) => { const a = argv.find((x) => x.startsWith('--' + n + '=')); return a ? a.split('=').slice(1).join('=') : d; };
const DEFAULT_TIMEOUT_MS = parseInt(opt('timeout', '300'), 10) * 1000;

const manifest = JSON.parse(fs.readFileSync(path.join(QA, 'manifest.json'), 'utf8'));
let stands = manifest.stands;
const only = opt('only', '');
if (only) stands = stands.filter((s) => only.split(',').includes(s.name));

if (argv.includes('--list')) {
  for (const s of stands) console.log(s.name.padEnd(14), '-', s.desc);
  process.exit(0);
}

function sh(line, timeoutMs) {
  // cmd /c без管道: вывод перенаправляется cmd-ом в файл; node каналы не открывает.
  // windowsVerbatimArguments => строку оборачиваем во внешние кавычки сами
  // (при /s cmd снимает крайнюю пару и исполняет внутренность как есть).
  const r = spawnSync('cmd.exe', ['/d', '/s', '/c', '"' + line + '"'], {
    stdio: 'ignore', windowsVerbatimArguments: true, timeout: timeoutMs, env: ISO_ENV,
  });
  if (r.error) return { exit: -1, error: r.error.message };
  const killed = r.signal === 'SIGTERM' || r.signal === 'SIGKILL';
  return { exit: killed ? -2 : (r.status === null ? -3 : r.status) };
}

function assertInside(dir, parentDir, what) {
  const rel = path.relative(path.resolve(parentDir), path.resolve(dir));
  if (!rel || rel.startsWith('..') || path.isAbsolute(rel))
    throw new Error('path assert: ' + what + ' вне разрешённого каталога (' + dir + ' !~ ' + parentDir + ')');
}

function ensureStage() {
  fs.mkdirSync(STAGE, { recursive: true });
  fs.mkdirSync(LOGS, { recursive: true });
  // Assert'ы: пишем/чистим/распаковываем строго в свой изолированный каталог.
  assertInside(ISO, path.join(ROOT, 'tools'), 'ISO');
  assertInside(STAGE, ISO, 'STAGE');
  if (argv.includes('--stage=robocopy')) {
    // легаси-режим: копия рабочего дерева main (не защищён от грязного worktree)
    const r = sh(`robocopy "${GAME}" "${STAGE}" /MIR /XD .godot .git /NFL /NDL /NJH /NJS /NP`, 300000);
    if (r.exit >= 8) throw new Error('robocopy main->stage failed rc=' + r.exit);
  } else {
    // По-умолчанию: стадзинг из git-объектов HEAD (`git archive`), рабочий каталог
    // main не читается и не трогается вовсе — не страшны ни грязный worktree,
    // ни LF-инциденты. Затем распаковка bsdtar СТРОГО в ISO/stage (assert выше).
    const zip = path.join(ISO, 'stage_src.zip');
    let r = sh(`git -C "${ROOT}" archive --format=zip -o "${zip}" HEAD -- pixel-rpg`, 300000);
    if (r.exit !== 0) throw new Error('git archive failed rc=' + r.exit);
    for (const c of fs.readdirSync(STAGE)) {
      if (c === '.godot') continue; // кэш импорта/классов переживает смену HEAD частично
      const t = path.join(STAGE, c);
      assertInside(t, STAGE, 'purge target');
      fs.rmSync(t, { recursive: true, force: true });
    }
    r = sh(`tar -xf "${zip}" -C "${path.dirname(STAGE)}"`, 300000);
    if (r.exit !== 0) throw new Error('tar extract failed rc=' + r.exit);
    fs.rmSync(zip, { force: true });
  }
  for (const f of fs.readdirSync(STAND)) fs.copyFileSync(path.join(STAND, f), path.join(STAGE, f));
}

function runImport() {
  if (argv.includes('--skip-import')) return true;
  const log = path.join(LOGS, '_import.log');
  process.stdout.write('[import] godot --headless --import ... ');
  const r = sh(`"${GODOT}" --headless --path "${STAGE}" --import > "${log}" 2>&1`, 600000);
  console.log('exit=' + r.exit);
  return r.exit === 0;
}

function parseVerdict(stand, logFile) {
  let text = '';
  try { text = fs.readFileSync(logFile, 'utf8'); } catch (e) { return { state: 'ERROR', pass: '-', fail: '-' }; }
  const mode = stand.parse.mode, re = new RegExp(stand.parse.re, 'g');
  const ms = [...text.matchAll(re)];
  if (!ms.length) return { state: 'NO_PARSE', pass: '-', fail: '-' };
  if (mode === 'pf') { const m = ms[ms.length - 1]; return { state: 'OK', pass: +m[1], fail: +m[2] }; }
  if (mode === 'xy') { const m = ms[ms.length - 1]; const p = +m[1], t = +m[2]; return { state: 'OK', pass: p, fail: t - p }; }
  if (mode === 'fails') { const m = ms[ms.length - 1]; return { state: 'OK', pass: '-', fail: +m[1] }; }
  if (mode === 'multi') { let p = 0, t = 0; for (const m of ms) { p += +m[1]; t += +m[2]; } return { state: 'OK', pass: p, fail: t - p }; }
  return { state: 'NO_PARSE', pass: '-', fail: '-' };
}

function wipeUserdata() {
  // После жёстко убитого/упавшего Godot ручки на app_userdata могут держаться
  // ещё мгновения (EPERM). Пробуем несколько раз; в крайнем случае чистим
  // содержимое и предупреждаем, не роняя батарею.
  for (let i = 0; i < 12; i++) {
    try { fs.rmSync(USERDATA, { recursive: true, force: true }); return; }
    catch (e) { const t = Date.now(); while (Date.now() - t < 500) { /* spin */ } }
  }
  try { for (const c of fs.readdirSync(USERDATA)) fs.rmSync(path.join(USERDATA, c), { recursive: true, force: true }); } catch (e) {}
  try {
    if (fs.readdirSync(USERDATA).length) console.log('[warn] user:// не удалось очистить полностью: ' + USERDATA);
  } catch (e) { console.log('[warn] user:// недоступен: ' + USERDATA); }
}

function main() {
  const t0 = Date.now();
  console.log('QA battery @ ' + ROOT);
  console.log('godot: ' + GODOT);
  console.log('stage: ' + STAGE);
  ensureStage();
  if (!runImport()) { console.log('FATAL: import failed, see ' + path.join(LOGS, '_import.log')); process.exit(1); }
  const rows = [];
  let green = 0, red = 0, sumP = 0, sumF = 0;
  for (const s of stands) {
    const name = s.name.padEnd(13);
    process.stdout.write('[run ] ' + name + ' ... ');
    // чистый user:// на каждую цепочку. Rmdir без ретраев ловил EPERM, пока
    // только что убитый Godot держит ручку на app_userdata, и валил батарею.
    // node сам ретраит EPERM/EBUSY/ENOTEMPTY только при maxRetries.
    try {
      fs.rmSync(USERDATA, { recursive: true, force: true, maxRetries: 3, retryDelay: 200 });
    } catch (e) {
      console.log('[warn] wipe user:// после 3 ретраев (200 мс): ' + e.code + ' — продолжаем');
    }
    let exits = [], lastLog = '', state = 'OK';
    for (let i = 0; i < s.run.length; i++) {
      lastLog = path.join(LOGS, s.name + '_' + (i + 1) + '.log');
      const r = sh(`"${GODOT}" --headless --path "${STAGE}" --fixed-fps 60 "res://${s.run[i]}" > "${lastLog}" 2>&1`, DEFAULT_TIMEOUT_MS);
      exits.push(r.exit === -2 ? 'TMO' : r.exit);
      if (r.exit === -2) { state = 'TIMEOUT'; break; }
      if (r.exit === -1) { state = 'ERROR'; break; }
    }
    let v = { state: 'ERROR', pass: '-', fail: '-' };
    if (state === 'OK') v = parseVerdict(s, lastLog);
    const pass = v.pass, fail = v.fail;
    let verdict;
    if (state === 'TIMEOUT') verdict = 'RED(timeout)';
    else if (v.state === 'NO_PARSE') verdict = 'RED(no_parse)';
    else if (v.state === 'ERROR') verdict = 'RED(error)';
    else if (+fail === 0) { verdict = 'GREEN'; green++; }
    else verdict = 'RED';
    if (verdict !== 'GREEN') red++;
    if (typeof pass === 'number') sumP += pass;
    if (typeof fail === 'number') sumF += fail;
    console.log(`${pass}/${fail} exit=${exits.join('/')} ${verdict}  log=${path.relative(ROOT, lastLog)}`);
    rows.push({ name: s.name, desc: s.desc, pass, fail, exit: exits.join('/'), verdict });
  }
  console.log('');
  console.log('STAND         PASS  FAIL  EXIT    VERDICT        DESC');
  for (const r of rows) {
    console.log(r.name.padEnd(13) + ' ' + String(r.pass).padStart(4) + '  ' + String(r.fail).padStart(4) + '  ' + r.exit.padEnd(7) + ' ' + r.verdict.padEnd(14) + ' ' + r.desc);
  }
  console.log('');
  console.log(`TOTAL: ${green} green / ${red} red | checks: ${sumP} pass / ${sumF} fail | ${((Date.now() - t0) / 1000).toFixed(0)}s`);
  console.log(red === 0 ? 'BATTERY VERDICT: GO' : 'BATTERY VERDICT: NO-GO');
  process.exit(red === 0 ? 0 : 1);
}

main();
