// I4A admin: a Cloudflare Worker that serves the admin page and the small
// JSON API the app polls. State lives in one Durable Object, so a change made
// on the admin page is visible to the app on its very next request.
//
//   GET  /             admin page
//   GET  /api/policy   current policy (read by the app; public)
//   POST /api/report   today's usage and whether Instagram is installed
//                      (sent by the app; public)
//   GET  /api/status   policy + latest usage (admin)
//   PUT  /api/policy   update the policy (admin)
//
// Policy: { locked, reelsLocked, limitEnabled, dailyLimitMinutes, updatedAt }.
// `locked` locks the time limit in the app; `reelsLocked` forces Reels
// hiding on and locks that switch.
//
// Admin requests need `Authorization: Bearer <ADMIN_TOKEN>`; set the token
// with `npx wrangler secret put ADMIN_TOKEN`.

import { DurableObject } from "cloudflare:workers";

const DEFAULT_POLICY = {
  locked: false,
  reelsLocked: false,
  limitEnabled: true,
  dailyLimitMinutes: 30,
  updatedAt: null,
};

export class Store extends DurableObject {
  async getPolicy() {
    // Policies saved by older versions lack newer fields.
    return { ...DEFAULT_POLICY, ...((await this.ctx.storage.get("policy")) ?? {}) };
  }

  async setPolicy(changes) {
    const policy = { ...(await this.getPolicy()), ...changes, updatedAt: new Date().toISOString() };
    await this.ctx.storage.put("policy", policy);
    return policy;
  }

  async getReport() {
    return (await this.ctx.storage.get("report")) ?? null;
  }

  async setReport(report) {
    await this.ctx.storage.put("report", { ...report, reportedAt: new Date().toISOString() });
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const store = env.STORE.get(env.STORE.idFromName("main"));

    try {
      if (url.pathname === "/" && request.method === "GET") {
        return new Response(ADMIN_PAGE, {
          headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
        });
      }

      if (url.pathname === "/api/policy" && request.method === "GET") {
        return json(await store.getPolicy());
      }

      if (url.pathname === "/api/report" && request.method === "POST") {
        const report = validateReport(await readJSON(request));
        if (!report) return json({ error: "invalid report" }, 400);
        await store.setReport(report);
        return json({ ok: true });
      }

      if (url.pathname === "/api/status" && request.method === "GET") {
        const denied = await checkAdmin(request, env);
        if (denied) return denied;
        return json({ policy: await store.getPolicy(), report: await store.getReport() });
      }

      if (url.pathname === "/api/policy" && request.method === "PUT") {
        const denied = await checkAdmin(request, env);
        if (denied) return denied;
        const changes = validatePolicyChanges(await readJSON(request));
        if (!changes) return json({ error: "invalid policy" }, 400);
        return json(await store.setPolicy(changes));
      }

      return json({ error: "not found" }, 404);
    } catch (error) {
      return json({ error: "server error" }, 500);
    }
  },
};

function json(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

async function readJSON(request) {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

async function checkAdmin(request, env) {
  if (!env.ADMIN_TOKEN) return json({ error: "ADMIN_TOKEN is not set" }, 500);
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  const a = new TextEncoder().encode(token);
  const b = new TextEncoder().encode(env.ADMIN_TOKEN);
  const ok = a.byteLength === b.byteLength && crypto.subtle.timingSafeEqual(a, b);
  return ok ? null : json({ error: "unauthorized" }, 401);
}

function validatePolicyChanges(body) {
  if (!body || typeof body !== "object") return null;
  const changes = {};
  if ("locked" in body) {
    if (typeof body.locked !== "boolean") return null;
    changes.locked = body.locked;
  }
  if ("reelsLocked" in body) {
    if (typeof body.reelsLocked !== "boolean") return null;
    changes.reelsLocked = body.reelsLocked;
  }
  if ("limitEnabled" in body) {
    if (typeof body.limitEnabled !== "boolean") return null;
    changes.limitEnabled = body.limitEnabled;
  }
  if ("dailyLimitMinutes" in body) {
    const m = body.dailyLimitMinutes;
    if (!Number.isInteger(m) || m < 1 || m > 1440) return null;
    changes.dailyLimitMinutes = m;
  }
  return Object.keys(changes).length ? changes : null;
}

function validateReport(body) {
  if (!body || typeof body !== "object") return null;
  const { day, usedSeconds, instagramInstalled } = body;
  if (typeof day !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(day)) return null;
  if (!Number.isInteger(usedSeconds) || usedSeconds < 0 || usedSeconds > 86400) return null;
  if (typeof instagramInstalled !== "boolean") return null;
  return { day, usedSeconds, instagramInstalled };
}

const ADMIN_PAGE = `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>I4A 관리자</title>
<style>
  :root {
    --bg: #f4f4f6; --card: #ffffff; --text: #111114; --muted: #6b6b75;
    --line: #e4e4e9; --accent: #e1306c; --accent-soft: #fde6ee; --ok: #1a9e5c; --warn: #d9534f;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0d0d10; --card: #18181c; --text: #f2f2f5; --muted: #9a9aa5;
      --line: #2a2a31; --accent: #ff4f8b; --accent-soft: #3a1525; --ok: #3ccf87; --warn: #ff6b66;
    }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; background: var(--bg); color: var(--text);
    font: 16px/1.45 -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Pretendard", system-ui, sans-serif;
  }
  main { max-width: 520px; margin: 0 auto; padding: 24px 16px 48px; }
  h1 { font-size: 22px; margin: 4px 0 2px; }
  .sub { color: var(--muted); font-size: 14px; margin-bottom: 20px; }
  .card { background: var(--card); border-radius: 18px; padding: 18px; margin-bottom: 14px; border: 1px solid var(--line); }
  .card h2 { font-size: 13px; font-weight: 600; color: var(--muted); margin: 0 0 12px; letter-spacing: .02em; }
  .usage { font-size: 30px; font-weight: 700; font-variant-numeric: tabular-nums; }
  .usage small { font-size: 16px; color: var(--muted); font-weight: 500; }
  .bar { height: 8px; border-radius: 4px; background: var(--line); overflow: hidden; margin: 12px 0 8px; }
  .bar > div { height: 100%; width: 0; background: var(--accent); transition: width .3s; }
  .meta { color: var(--muted); font-size: 13px; }
  .row { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 10px 0; }
  .row + .row { border-top: 1px solid var(--line); }
  .row .label { font-weight: 600; }
  .row .hint { color: var(--muted); font-size: 13px; font-weight: 400; }
  .switch { position: relative; width: 51px; height: 31px; flex: none; }
  .switch input { opacity: 0; width: 0; height: 0; }
  .switch span { position: absolute; inset: 0; border-radius: 31px; background: var(--line); transition: .2s; cursor: pointer; }
  .switch span::before { content: ""; position: absolute; width: 27px; height: 27px; left: 2px; top: 2px; border-radius: 50%; background: #fff; transition: .2s; box-shadow: 0 1px 3px rgba(0,0,0,.25); }
  .switch input:checked + span { background: var(--ok); }
  .switch input:checked + span::before { transform: translateX(20px); }
  .chips { display: flex; flex-wrap: wrap; gap: 8px; margin: 6px 0 14px; }
  .chip { border: 1px solid var(--line); background: transparent; color: var(--text); border-radius: 999px; padding: 8px 14px; font: inherit; font-size: 15px; cursor: pointer; }
  .chip.on { background: var(--accent); border-color: var(--accent); color: #fff; font-weight: 600; }
  .stepper { display: flex; align-items: center; gap: 10px; }
  .stepper button { width: 44px; height: 44px; border-radius: 12px; border: 1px solid var(--line); background: transparent; color: var(--text); font-size: 22px; cursor: pointer; }
  .stepper input { width: 90px; height: 44px; text-align: center; font: inherit; font-size: 20px; font-weight: 700; border-radius: 12px; border: 1px solid var(--line); background: transparent; color: var(--text); }
  .disabled { opacity: .45; pointer-events: none; }
  .status { position: fixed; left: 50%; bottom: 20px; transform: translateX(-50%); background: var(--text); color: var(--bg); padding: 8px 16px; border-radius: 999px; font-size: 14px; opacity: 0; transition: opacity .2s; pointer-events: none; }
  .status.show { opacity: 1; }
  .status.err { background: var(--warn); color: #fff; }
  form input[type=password] { width: 100%; height: 46px; padding: 0 14px; border-radius: 12px; border: 1px solid var(--line); background: transparent; color: var(--text); font: inherit; margin: 8px 0 12px; }
  .primary { width: 100%; height: 46px; border: 0; border-radius: 12px; background: var(--accent); color: #fff; font: inherit; font-weight: 600; cursor: pointer; }
  .link { background: none; border: 0; color: var(--muted); font: inherit; font-size: 13px; text-decoration: underline; cursor: pointer; padding: 0; }
  [hidden] { display: none !important; }
</style>
</head>
<body>
<main>
  <h1>I4A 관리자</h1>
  <div class="sub">사용자의 인스타그램 시간 제한을 관리해요. 바꾸면 바로 저장되고, 앱에는 20초 안에 반영돼요.</div>

  <section id="login" class="card" hidden>
    <h2>관리자 비밀번호</h2>
    <form id="loginForm">
      <input id="token" type="password" autocomplete="current-password" placeholder="ADMIN_TOKEN" required>
      <button class="primary" type="submit">들어가기</button>
    </form>
  </section>

  <div id="app" hidden>
    <section class="card">
      <h2>오늘 사용</h2>
      <div class="usage" id="usageText">-</div>
      <div class="bar"><div id="usageBar"></div></div>
      <div class="meta" id="usageMeta">앱에서 아직 보고가 없어요.</div>
    </section>

    <section class="card">
      <h2>인스타그램 앱</h2>
      <div class="row" style="padding:0">
        <div><div class="label" id="igText">-</div><div class="hint" id="igMeta">앱에서 아직 보고가 없어요.</div></div>
        <div id="igBadge" style="font-size:28px"></div>
      </div>
    </section>

    <section class="card">
      <h2>관리</h2>
      <div class="row">
        <div><div class="label">릴스 숨기기 잠금</div><div class="hint">켜면 릴스가 항상 숨겨지고, 앱에서 끌 수 없어요</div></div>
        <label class="switch"><input type="checkbox" id="reelsLocked"><span></span></label>
      </div>
      <div class="row">
        <div><div class="label">시간 제한 잠금</div><div class="hint">켜면 앱에서 시간 제한 메뉴를 만질 수 없어요</div></div>
        <label class="switch"><input type="checkbox" id="locked"><span></span></label>
      </div>
      <div class="row">
        <div><div class="label">시간 제한 사용</div><div class="hint">끄면 시간 제한 없이 쓸 수 있어요</div></div>
        <label class="switch"><input type="checkbox" id="limitEnabled"><span></span></label>
      </div>
    </section>

    <section class="card" id="limitCard">
      <h2>하루 허용 시간</h2>
      <div class="chips" id="chips"></div>
      <div class="stepper">
        <button type="button" id="minus" aria-label="5분 줄이기">−</button>
        <input id="minutes" type="number" inputmode="numeric" min="1" max="1440" step="1">
        <button type="button" id="plus" aria-label="5분 늘리기">+</button>
        <span class="meta">분</span>
      </div>
    </section>

    <div class="meta" style="text-align:center">
      <span id="updated"></span> · <button class="link" id="logout">로그아웃</button>
    </div>
  </div>
</main>
<div class="status" id="status"></div>

<script>
(function () {
  var KEY = 'i4a-admin-token';
  var PRESETS = [15, 30, 45, 60, 90, 120, 180];
  var token = null;
  var policy = null;
  var report = null;
  var saving = 0;
  var minutesTimer = null;
  var $ = function (id) { return document.getElementById(id); };

  try { token = localStorage.getItem(KEY); } catch (e) {}

  function fmt(seconds) {
    var s = Math.max(0, seconds | 0);
    if (s < 60) return s + '초';
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
    if (!h) return m + '분';
    return m ? h + '시간 ' + m + '분' : h + '시간';
  }

  function ago(iso) {
    if (!iso) return '';
    var diff = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
    if (diff < 60) return '방금 전';
    if (diff < 3600) return Math.floor(diff / 60) + '분 전';
    if (diff < 86400) return Math.floor(diff / 3600) + '시간 전';
    return Math.floor(diff / 86400) + '일 전';
  }

  var statusTimer = null;
  function flash(text, isError) {
    var el = $('status');
    el.textContent = text;
    el.className = 'status show' + (isError ? ' err' : '');
    clearTimeout(statusTimer);
    statusTimer = setTimeout(function () { el.className = 'status'; }, 1600);
  }

  function api(method, path, body) {
    return fetch(path, {
      method: method,
      headers: { 'authorization': 'Bearer ' + token, 'content-type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
      cache: 'no-store'
    }).then(function (res) {
      if (res.status === 401) { logout('비밀번호가 맞지 않아요'); throw new Error('unauthorized'); }
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return res.json();
    });
  }

  function render(status) {
    policy = status.policy;
    report = status.report;
    $('locked').checked = policy.locked;
    $('reelsLocked').checked = !!policy.reelsLocked;
    $('limitEnabled').checked = policy.limitEnabled;
    if (document.activeElement !== $('minutes')) $('minutes').value = policy.dailyLimitMinutes;
    $('limitCard').classList.toggle('disabled', !policy.limitEnabled);
    renderChips();
    $('updated').textContent = policy.updatedAt ? '마지막 변경 ' + ago(policy.updatedAt) : '';

    if (report) {
      var limit = policy.dailyLimitMinutes * 60;
      $('usageText').innerHTML = fmt(report.usedSeconds) +
        (policy.limitEnabled ? ' <small>/ ' + fmt(limit) + '</small>' : '');
      $('usageBar').style.width = policy.limitEnabled ? Math.min(100, report.usedSeconds / limit * 100) + '%' : '0';
      $('usageMeta').textContent = report.day + ' · 앱 마지막 연결 ' + ago(report.reportedAt);
      $('igText').textContent = report.instagramInstalled ? '설치되어 있어요' : '설치되어 있지 않아요';
      $('igText').style.color = report.instagramInstalled ? 'var(--warn)' : 'var(--ok)';
      $('igBadge').textContent = report.instagramInstalled ? '⚠️' : '✅';
      $('igMeta').textContent = '마지막 확인 ' + ago(report.reportedAt);
    }
  }

  function renderChips() {
    var box = $('chips');
    box.innerHTML = '';
    PRESETS.forEach(function (m) {
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'chip' + (policy && policy.dailyLimitMinutes === m ? ' on' : '');
      b.textContent = fmt(m * 60);
      b.onclick = function () { save({ dailyLimitMinutes: m }); };
      box.appendChild(b);
    });
  }

  function load() {
    if (!token || saving) return Promise.resolve();
    return api('GET', '/api/status').then(render).catch(function () {});
  }

  function save(changes) {
    // Show the change right away; the server answer confirms it.
    if (policy) { Object.assign(policy, changes); render({ policy: policy, report: report }); }
    saving++;
    return api('PUT', '/api/policy', changes)
      .then(function (p) { policy = p; flash('저장됨'); })
      .catch(function (e) { if (e.message !== 'unauthorized') flash('저장하지 못했어요', true); })
      .then(function () { saving--; return load(); });
  }

  function setMinutes(value) {
    var m = Math.round(Number(value));
    if (!isFinite(m)) return;
    m = Math.min(1440, Math.max(1, m));
    $('minutes').value = m;
    save({ dailyLimitMinutes: m });
  }

  function logout(message) {
    token = null;
    try { localStorage.removeItem(KEY); } catch (e) {}
    $('app').hidden = true;
    $('login').hidden = false;
    if (message) flash(message, true);
  }

  function start() {
    $('login').hidden = true;
    $('app').hidden = false;
    load();
  }

  $('loginForm').onsubmit = function (event) {
    event.preventDefault();
    token = $('token').value.trim();
    try { localStorage.setItem(KEY, token); } catch (e) {}
    start();
  };
  $('logout').onclick = function () { logout(); };
  $('locked').onchange = function () { save({ locked: this.checked }); };
  $('reelsLocked').onchange = function () { save({ reelsLocked: this.checked }); };
  $('limitEnabled').onchange = function () { save({ limitEnabled: this.checked }); };
  $('minus').onclick = function () { setMinutes((Number($('minutes').value) || 0) - 5); };
  $('plus').onclick = function () { setMinutes((Number($('minutes').value) || 0) + 5); };
  $('minutes').oninput = function () {
    clearTimeout(minutesTimer);
    var value = this.value;
    if (value === '') return;
    minutesTimer = setTimeout(function () { setMinutes(value); }, 600);
  };

  if (token) { start(); } else { $('login').hidden = false; }
  setInterval(load, 10000);
  document.addEventListener('visibilitychange', function () { if (!document.hidden) load(); });
})();
</script>
</body>
</html>`;
