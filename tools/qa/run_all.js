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
//
// ── t66: укрепление процессной гигиены (находки аудитора t60/t64, пункты 3/4/5) ─────────────────
//  A. ДЕРЕВО ПРОЦЕССОВ. node при таймауте снимает только прямого ребёнка — cmd.exe,
//     а Godot-внук оставался сиротой и держал лог и user:// (источник ложных
//     RED(no_parse) на следующем прогоне). Проверено экспериментом: сирота живёт,
//     но Windows НЕ переприсваивает родителя, поэтому дети мёртвого cmd находятся по
//     ParentProcessId. Теперь при таймауте: taskkill /T /F по PID, затем выборочное
//     Stop-Process по ParentProcessId, затем — по имени Godot со ссылкой на НАШ
//     каталог стенда (чужие Godot и редактор не трогаем никогда).
//  B. --skip-import больше не врёт: без .godot/imported стенд невалиден для
//     арт-зависимых suites (портреты/тайлы/атласы краснеют ЛОЖНО). Флаг оставлен
//     (он полезен для повторного прогона по уже импортированному stage), но печатает
//     крупную метку, а если импорта не было вовсе — работа падает, а не показывает
//     8 красных стендов.
//  C. ПАРАЛЛЕЛЬНЫЕ ПРОГОНЫ. Локи tools/appdata_qa/runner.lock + проверка живых Godot
//     нашего стенда: коллизия → явная ошибка «parallel run detected». При живом
//     соседе изолированный повтор НЕ выполняется (общий user:// + EPERM на wipe
//     дали бы и ложный RED, и ложный GREEN).
//  B. ИМПОРТ. Редкий пад импорта (0xC0000005 на шрифте, FATAL ENGINE BUG) — рецепт
//     «удалить tools/appdata_qa/stage и повторить» зашит: один авто-ретрай с чистого
//     stage. Тестовый хук QA_TEST_IMPORT_FAIL=1 заставляет первую попытку считаться
//     упавшей (проверка этого же пути в CI-экспериментах).
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
const STAGE_ROOT = path.join(ISO, 'stage');
const STAGE = path.join(STAGE_ROOT, 'pixel-rpg');
const LOGS = path.join(ISO, 'logs');
const USERDATA = path.join(ISO, 'app', 'Godot', 'app_userdata');
const LOCK = path.join(ISO, 'runner.lock');
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
const SKIP_IMPORT = argv.includes('--skip-import');

function FATAL(msg) {
  console.log('');
  console.log('FATAL: ' + msg);
  process.exit(1);
}

const manifest = JSON.parse(fs.readFileSync(path.join(QA, 'manifest.json'), 'utf8'));
let stands = manifest.stands;
const only = opt('only', '');
if (only) stands = stands.filter((s) => only.split(',').includes(s.name));

if (argv.includes('--list')) {
  for (const s of stands) console.log(s.name.padEnd(14), '-', s.desc);
  process.exit(0);
}

function sh(line, timeoutMs) {
  // cmd /c без пайпов: вывод перенаправляется cmd-ом в файл; node каналы не открывает.
  // windowsVerbatimArguments => строку оборачиваем во внешние кавычки сами
  // (при /s cmd снимает крайнюю пару и исполняет внутренность как есть).
  const r = spawnSync('cmd.exe', ['/d', '/s', '/c', '"' + line + '"'], {
    stdio: 'ignore', windowsVerbatimArguments: true, timeout: timeoutMs, env: ISO_ENV,
  });
  // ВАЖНО (t66): при таймауте node ставит И signal, И error=ETIMEDOUT; прежний
  // порядок проверок трактовал это как RED(error) и дерево не убивал вовсе.
  const killed = r.signal === 'SIGTERM' || r.signal === 'SIGKILL' ||
    (r.error && /ETIMEDOUT/i.test(r.error.message));
  if (killed) killTree(r.pid, 'таймаут ' + timeoutMs + ' мс: ' + line.slice(0, 90));
  else if (r.error) return { exit: -1, error: r.error.message, pid: r.pid };
  return { exit: killed ? -2 : (r.status === null ? -3 : r.status), pid: r.pid };
}

// ── обслуга процессов (t66 A/C) ──────────────────────────────────────────────
// PowerShell запускается без пайпов (stdio:'ignore'), вывод — в файл: в песочнице
// DSH именованные каналы недоступны, а redirekt средствами cmd работает.
function ps(line, timeoutMs) {
  const r = spawnSync('powershell.exe',
    ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', line],
    { stdio: 'ignore', timeout: timeoutMs || 60000, env: ISO_ENV });
  return r.status === 0;
}

function psLines(line, tag, timeoutMs) {
  const f = path.join(LOGS, '_ps_' + tag + '_' + process.pid + '.txt');
  fs.mkdirSync(LOGS, { recursive: true });
  try { fs.rmSync(f, { force: true }); } catch (e) {}
  ps(line + ' | Out-File -Encoding ascii -Width 8192 "' + f + '"', timeoutMs);
  if (!fs.existsSync(f)) return [];
  let t = '';
  try { t = fs.readFileSync(f, 'utf8'); } catch (e) { return []; }
  try { fs.rmSync(f, { force: true }); } catch (e) {}   // свой файл-побочник не копим
  return t.split(/\r?\n/).map((x) => x.trim()).filter((x) => x.length);
}

// PID жив? (0-й сигнал ничего не убивает, но отличает «жив» от «нет такого»)
function pidAlive(pid) {
  if (!pid || pid <= 0) return false;
  try { process.kill(pid, 0); return true; }
  catch (e) { return e.code === 'EPERM'; }
}

// PID'ы Godot, в командной строке которых упомянут наш путь (только НАШИ прогоны:
// редактор и чужие стенды в другой копии репозитория под фильтр не попадают)
function ourGodotPids(needle) {
  return psLines(
    'Get-CimInstance Win32_Process -Filter "Name LIKE \'Godot%\'" | Where-Object { $_.CommandLine -like \'*'
      + needle + '*\' } | ForEach-Object { "$($_.ProcessId)" }', 'procs')
    .map((x) => parseInt(x, 10)).filter((x) => x > 0);
}

function killTree(pid, why) {
  if (!pid) return 0;
  let killedDesc = 0;
  console.log('');
  console.log('[killtree] ' + why);
  // 1) если родитель ещё жив — штатный taskkill снимает всё дерево разом
  sh('taskkill /T /F /PID ' + pid, 30000);
  // 2) родитель уже мёртв (node снял cmd по таймауту) — спускаемся по дереву сами.
  //    Windows НЕ меняет ParentProcessId после смерти родителя, сироты находится.
  //    Глубина >1 обязательна: Godot *_console.exe — обёртка, настоящий движок её
  //    ребёнок (замер t66: 2 попытки x 2 процесса = 4 сироты на пустом таймауте).
  let level = [pid];
  for (let depth = 0; depth < 5 && level.length; depth++) {
    const filter = level.map((p) => 'ParentProcessId=' + p).join(' or ');
    const kids = psLines('Get-CimInstance Win32_Process -Filter "' + filter
      + '" | ForEach-Object { "$($_.ProcessId)" }', 'tree');
    for (const k of kids) ps('Stop-Process -Id ' + k + ' -Force -ErrorAction SilentlyContinue', 20000);
    killedDesc += kids.length;
    level = kids;
  }
  // 3) подчистка: наш Godot, до сих пор держащий путь этого стенда (сироты прошлых
  //    падений). Безопасно, потому что параллельный прогон отсекается локом ниже.
  const ours = ourGodotPids(STAGE_ROOT);
  for (const p of ours) ps('Stop-Process -Id ' + p + ' -Force -ErrorAction SilentlyContinue', 30000);
  console.log('[killtree] снято по PPID-дереву: ' + killedDesc + ', по пути стенда: ' + ours.length);
  return ours.length;
}

// ── лок от параллельного прогона (t66 C) ──────────────────────────────────────
function acquireLock() {
  fs.mkdirSync(ISO, { recursive: true });
  fs.mkdirSync(LOGS, { recursive: true });
  if (fs.existsSync(LOCK)) {
    let raw = '';
    try { raw = fs.readFileSync(LOCK, 'utf8'); } catch (e) { raw = ''; }
    const m = /"pid":\s*(\d+)/.exec(raw);
    const other = m ? parseInt(m[1], 10) : 0;
    if (other && other !== process.pid && pidAlive(other)) {
      FATAL('parallel run detected: этот же набор стендов уже запускает процесс PID='
        + other + ' (лок ' + path.relative(ROOT, LOCK) + ', ' + raw.replace(/\s+/g, ' ').slice(0, 160) + '). '
        + 'Параллельные прогоны делят user:// и логи → результаты неверны. Дождись конца или удали лок, если тот процесс убит.');
    }
    console.log('[lock] снят труп-лок прежнего прогона: ' + raw.replace(/\s+/g, ' ').slice(0, 160));
  }
  fs.writeFileSync(LOCK, JSON.stringify({ pid: process.pid, stage: STAGE_ROOT, args: argv, at: new Date().toISOString() }));
  process.on('exit', () => {
    // снимаем только СВОЙ лок: если за это время его пересоздал
    // другой прогон — чужой файл не трогаем
    try {
      const cur = JSON.parse(fs.readFileSync(LOCK, 'utf8'));
      if (cur && cur.pid === process.pid) fs.rmSync(LOCK, { force: true });
    } catch (e) {}
  });
}

// Живые чужие Godot нашего стенда (для решения «можно ли повторять изолированно»)
function neighborGodots() { return ourGodotPids(STAGE_ROOT); }

function assertInside(dir, parentDir, what) {
  const rel = path.relative(path.resolve(parentDir), path.resolve(dir));
  if (!rel || rel.startsWith('..') || path.isAbsolute(rel))
    throw new Error('path assert: ' + what + ' вне разрешённого каталога (' + dir + ' !~ ' + parentDir + ')');
}

function purge(dir, what) {
  assertInside(dir, ISO, what || 'purge target');
  fs.rmSync(dir, { recursive: true, force: true, maxRetries: 6, retryDelay: 250 });
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
    r = sh(`tar -xf "${zip}" -C "${STAGE_ROOT}"`, 300000);
    if (r.exit !== 0) throw new Error('tar extract failed rc=' + r.exit);
    fs.rmSync(zip, { force: true });
  }
  for (const f of fs.readdirSync(STAND)) fs.copyFileSync(path.join(STAND, f), path.join(STAGE, f));
}

// Есть ли в стенде следы импорта: без них арт-зависимые suites невалидны (t66 B)
function importedFiles() {
  const d = path.join(STAGE, '.godot', 'imported');
  try { return fs.readdirSync(d).filter((x) => /\.(ctex|cppextrem|material|res|scn|txt)$/i.test(x)).length; }
  catch (e) { return 0; }
}

// --skip-import ВЫВЕДЕН ИЗ ОБОРОТА (t66). Замер на песочнице g22: сразу после
// успешного полного импорта тот же qa_lp со --skip-import даёт 325 pass / 25 fail
// вместо 420/0 на ПОЛНОМ кэше .godot/imported (130 файлов). Причина структурная:
// ensureStage() каждый прогон заново распаковывает исходники из git archive, их
// mtime свежее кэша, и без шага --import Godot считает импортированные ресурсы
// устаревшими — res://assets/*.png приходят null. Молча пропущенный импорт =
// гарантированная ложная тревога (в t64 так «упало» 8 арт-стендов). Флаг принят
// только ради совместимости старых команд: печатает баннер ниже, а импорт
// выполняется в любом случае — результат честный.
function announceSkipImport() {
  if (!SKIP_IMPORT) return;
  console.log('');
  console.log('!!!!!!!!!! --skip-import БОЛЬШЕ НЕ ПРОПУСКАЕТ ИМПОРТ (t66) !!!!!!!!!!');
  console.log('! ensureStage() заново распаковывает исходники каждого прогона, их');
  console.log('! mtime свежее кэша .godot/imported, и без импорта арт-ресурсы');
  console.log('! приходят null: qa_lp на полном кэше даёт 325/25 вместо 420/0.');
  console.log('! Без импорта арт-стенды НЕВАЛИДНЫ, поэтому импорт выполняется');
  console.log('! всегда. Команду принимаем для совместимости, результат честный.');
  console.log('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
}

function runImport() {
  announceSkipImport();
  const log = path.join(LOGS, '_import.log');
  process.stdout.write('[import] godot --headless --import ... ');
  let r = sh(`"${GODOT}" --headless --path "${STAGE}" --import > "${log}" 2>&1`, 600000);
  const forced = process.env.QA_TEST_IMPORT_FAIL === '1';
  console.log('exit=' + r.exit + (forced ? ' (QA_TEST_IMPORT_FAIL=1 → считаем упавшим)' : '')
    + ', импортированных ресурсов в кэше: ' + importedFiles());
  if (r.exit === 0 && !forced) return true;
  // Рецепт из практики: редкий пад импорта (0xC0000005 access violation на шрифте)
  // не повторяем «как есть» — чистим stage целиком и импортируем один раз заново.
  const code = r.exit >>> 0;
  console.log('[import] попытка 1 провалилась (exit=' + r.exit
    + (code === 0xC0000005 ? ' = 0xC0000005 access violation' : '')
    + '); чистим ' + path.relative(ROOT, STAGE_ROOT) + ' и повторяем один раз');
  purge(STAGE_ROOT, 'stage root');
  ensureStage();
  process.stdout.write('[import] повтор: godot --headless --import ... ');
  r = sh(`"${GODOT}" --headless --path "${STAGE}" --import > "${log}" 2>&1`, 600000);
  console.log('exit=' + r.exit);
  if (r.exit === 0) { console.log('[import] повтор успешен'); return true; }
  return false;
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

function main() {
  const t0 = Date.now();
  console.log('QA battery @ ' + ROOT);
  console.log('godot: ' + GODOT);
  console.log('stage: ' + STAGE);
  // t66 C: до любой работы с stage/user:// — лок и смотр на живые Godot нашего стенда.
  acquireLock();
  const left = neighborGodots();
  if (left.length) {
    // Лока у нас нет (мы её ещё не брали) либо она наша снятая — значит это сироты
    // прежних убитых/упавших прогонов: они держат логи и user:// → убираем.
    console.log('[warn] живых Godot со ссылкой на этот стенд: ' + left.join(',') + ' — убираем сирот');
    for (const p of left) ps('Stop-Process -Id ' + p + ' -Force -ErrorAction SilentlyContinue', 30000);
  }
  ensureStage();
  if (!runImport()) { console.log('FATAL: import failed (повтор с чистого stage тоже), see ' + path.join(LOGS, '_import.log')); process.exit(1); }
  const rows = [];
  let green = 0, red = 0, sumP = 0, sumF = 0;
  let retriesUsed = 0; const retriedNames = [];
  const retrySkipped = [];
  // t43: один автоматический изолированный повтор для RED-стенда (флейки тайминга/RNG
  // под параллельной нагрузкой). Зелёный стенд ретрай НЕ касается. Честная видимость:
  // вердикт «GREEN(retry)» виден в таблице и в итоговой строке — зелёный через ретрай
  // не прячется под обычный GREEN.
  // t66 C: «изолированный» повтор изолирован ровно настолько, насколько чист user://.
  // При живом соседнем Godot это не так → повтор пропускаем явно, а не выполняем тайком.
  function runStandalone(s, logPrefix) {
    try {
      fs.rmSync(USERDATA, { recursive: true, force: true, maxRetries: 3, retryDelay: 200 });
    } catch (e) {
      const nb = neighborGodots();
      console.log('[warn] wipe user:// после 3 ретраев (200 мс): ' + e.code
        + (nb.length ? ' || живые Godot этого стенда: ' + nb.join(',') + ' (parallel run detected?)' : '')
        + ' — продолжаем');
    }
    let exits = [], lastLog = '', state = 'OK';
    for (let i = 0; i < s.run.length; i++) {
      lastLog = path.join(LOGS, s.name + '_' + logPrefix + (i + 1) + '.log');
      // Лог обязан принадлежать ЭТОМУ прогону: если Godot не запустился (не нашёлся
      // exe, упал cmd, каталог недоступен), прошлый файл дал бы ложный GREEN из
      // прежнего прогона. Сносим заранее — нет лога, нет вердикта (parseVerdict →
      // ERROR), а не чужой успех.
      try { fs.rmSync(lastLog, { force: true }); } catch (e) {}
      const r = sh(`"${GODOT}" --headless --path "${STAGE}" --fixed-fps 60 "res://${s.run[i]}" > "${lastLog}" 2>&1`, DEFAULT_TIMEOUT_MS);
      exits.push(r.exit === -2 ? 'TMO' : r.exit);
      if (r.exit === -2) { state = 'TIMEOUT'; break; }
      if (r.exit === -1) { state = 'ERROR'; break; }
    }
    let v = { state: 'ERROR', pass: '-', fail: '-' };
    if (state === 'OK') v = parseVerdict(s, lastLog);
    let verdict;
    if (state === 'TIMEOUT') verdict = 'RED(timeout)';
    else if (v.state === 'NO_PARSE') verdict = 'RED(no_parse)';
    else if (v.state === 'ERROR') verdict = 'RED(error)';
    else if (+v.fail === 0) verdict = 'GREEN';
    else verdict = 'RED';
    return { exits, lastLog, v, verdict };
  }
  for (const s of stands) {
    const name = s.name.padEnd(13);
    process.stdout.write('[run ] ' + name + ' ... ');
    let att = runStandalone(s, '');
    if (att.verdict !== 'GREEN') {
      const nb = neighborGodots();
      console.log('');
      if (nb.length) {
        console.log('[skip-retry] ' + s.name + ': ' + att.verdict + ' → повтор ПРОПУЩЕН: parallel run detected'
          + ' (живые Godot этого стенда: ' + nb.join(',') + '). Общий user:// сделал бы повтор'
          + ' неизолированным: ложный RED или ложный GREEN. Разберись с соседом и повтори стенд.');
        retrySkipped.push(s.name);
      } else {
        console.log('[retry] ' + s.name + ': ' + att.verdict + ' → один изолированный повтор');
        retriesUsed++; retriedNames.push(s.name);
        att = runStandalone(s, 'retry_');
        if (att.verdict === 'GREEN') att.verdict = 'GREEN(retry)';
        else att.verdict += '(retry тоже)';
      }
    }
    const pass = att.v.pass, fail = att.v.fail;
    if (att.verdict.startsWith('GREEN')) green++; else red++;
    if (typeof pass === 'number') sumP += pass;
    if (typeof fail === 'number') sumF += fail;
    console.log(`${pass}/${fail} exit=${att.exits.join('/')} ${att.verdict}  log=${path.relative(ROOT, att.lastLog)}`);
    rows.push({ name: s.name, desc: s.desc, pass, fail, exit: att.exits.join('/'), verdict: att.verdict });
  }
  console.log('');
  console.log('STAND         PASS  FAIL  EXIT    VERDICT        DESC');
  for (const r of rows) {
    console.log(r.name.padEnd(13) + ' ' + String(r.pass).padStart(4) + '  ' + String(r.fail).padStart(4) + '  ' + r.exit.padEnd(7) + ' ' + r.verdict.padEnd(14) + ' ' + r.desc);
  }
  console.log('');
  console.log(`TOTAL: ${green} green / ${red} red | checks: ${sumP} pass / ${sumF} fail | ${((Date.now() - t0) / 1000).toFixed(0)}s` + (retriesUsed ? ' | auto-retries: ' + retriesUsed + ' (' + retriedNames.join(', ') + ')' : '') + (retrySkipped.length ? ' | повтор пропущен (сосед): ' + retrySkipped.join(', ') : ''));
  console.log(red === 0 ? 'BATTERY VERDICT: GO' + (retriedNames.length ? ' (зелёный через ретрай: ' + retriedNames.join(', ') + ')' : '') : 'BATTERY VERDICT: NO-GO');
  process.exit(red === 0 ? 0 : 1);
}

main();
