#!/usr/bin/env node
/**
 * ACC Auto-Apply Daemon (NO fetch; uses http/https stdlib)
 * Watches:  <repo>/AI_BRAIN/inbox/patches/*.diff
 * Posts:    http://127.0.0.1:8787/patch/apply  (ACC_URL env overrides)
 */
import fs from "fs";
import path from "path";
import http from "http";
import https from "https";

const repoRoot = process.cwd();
const inboxDir   = path.join(repoRoot, "AI_BRAIN", "inbox", "patches");
const appliedDir = path.join(repoRoot, "AI_BRAIN", "inbox", "applied");
const failedDir  = path.join(repoRoot, "AI_BRAIN", "inbox", "failed");

const ACC_URL = process.env.ACC_URL || "http://127.0.0.1:8787";
const PROVIDER = process.env.ACC_PROVIDER || "claude";

function ensureDir(p) { if (!fs.existsSync(p)) fs.mkdirSync(p, { recursive: true }); }
function nowStamp() { return new Date().toISOString().replace(/[:.]/g, "-"); }

function parseMeta(filename) {
  const base = filename.replace(/\.diff$/i, "");
  const parts = base.split("__").filter(Boolean);
  const taskId = (parts[0] || "TASK_AUTO").slice(0, 80);
  const reason = (parts[1] || "auto").slice(0, 120);
  return { taskId, reason };
}

function postJson(urlStr, pathname, bodyObj, timeoutMs=15000) {
  return new Promise((resolve, reject) => {
    let url;
    try { url = new URL(urlStr); } catch (e) { return reject(new Error("Bad ACC_URL: " + urlStr)); }

    const data = JSON.stringify(bodyObj);
    const isHttps = url.protocol === "https:";
    const mod = isHttps ? https : http;

    const req = mod.request({
      hostname: url.hostname,
      port: url.port || (isHttps ? 443 : 80),
      path: pathname,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(data),
      },
      timeout: timeoutMs,
    }, (res) => {
      let buf = "";
      res.setEncoding("utf8");
      res.on("data", (chunk) => buf += chunk);
      res.on("end", () => resolve({ status: res.statusCode || 0, text: buf }));
    });

    req.on("timeout", () => { req.destroy(new Error("timeout")); });
    req.on("error", (err) => reject(err));
    req.write(data);
    req.end();
  });
}

async function accHealthy() {
  try {
    const r = await postJson(ACC_URL, "/diffpack/poke", { reason: "health", changed_files: [] }, 5000);
    // /diffpack/poke expects changed_files; empty is ok and should return 200 or 4xx; we treat any response as "reachable".
    return r.status > 0;
  } catch {
    return false;
  }
}

async function postPatch({ taskId, reason, patch }) {
  const body = { provider: PROVIDER, task_id: taskId, reason, patch };
  return postJson(ACC_URL, "/patch/apply", body, 30000);
}

async function handleFile(fullPath) {
  const filename = path.basename(fullPath);
  if (!filename.toLowerCase().endsWith(".diff")) return;
  if (filename.startsWith(".") || filename.endsWith(".partial.diff")) return;

  let patch = "";
  try { patch = fs.readFileSync(fullPath, "utf8"); }
  catch (e) { console.error("[ACC-DAEMON] read failed:", filename, e?.message || e); return; }

  if (!patch.includes("diff --git")) {
    const outName = `${nowStamp()}__${filename}.rejected.txt`;
    fs.writeFileSync(path.join(failedDir, outName), `Rejected: not a unified diff\n\n${patch}`);
    fs.renameSync(fullPath, path.join(failedDir, `${nowStamp()}__${filename}`));
    console.error("[ACC-DAEMON] rejected (not unified diff):", filename);
    return;
  }

  const { taskId, reason } = parseMeta(filename);
  console.log(`[ACC-DAEMON] applying: ${filename} -> task_id=${taskId} reason=${reason}`);

  // wait for ACC to be reachable (quick retries)
  for (let i=0; i<10; i++) {
    if (await accHealthy()) break;
    await new Promise(r => setTimeout(r, 300));
  }

  try {
    const r = await postPatch({ taskId, reason, patch });
    const stamp = nowStamp();

    if (r.status >= 200 && r.status < 300) {
      fs.writeFileSync(path.join(appliedDir, `${stamp}__${filename}.response.json`), r.text);
      fs.renameSync(fullPath, path.join(appliedDir, `${stamp}__${filename}`));
      console.log("[ACC-DAEMON] ok:", filename);
    } else {
      fs.writeFileSync(path.join(failedDir, `${stamp}__${filename}.response.txt`), r.text);
      fs.renameSync(fullPath, path.join(failedDir, `${stamp}__${filename}`));
      console.error("[ACC-DAEMON] failed:", filename, "status=", r.status);
    }
  } catch (e) {
    const stamp = nowStamp();
    fs.writeFileSync(path.join(failedDir, `${stamp}__${filename}.exception.txt`), String(e?.stack || e));
    try { fs.renameSync(fullPath, path.join(failedDir, `${stamp}__${filename}`)); } catch {}
    console.error("[ACC-DAEMON] exception:", filename, e?.message || e);
  }
}

function scanOnce() {
  const files = fs.readdirSync(inboxDir);
  for (const f of files) handleFile(path.join(inboxDir, f));
}

function main() {
  ensureDir(inboxDir); ensureDir(appliedDir); ensureDir(failedDir);

  console.log("[ACC-DAEMON] repoRoot:", repoRoot);
  console.log("[ACC-DAEMON] watching:", inboxDir);
  console.log("[ACC-DAEMON] acc url:", ACC_URL);

  scanOnce();

  fs.watch(inboxDir, { persistent: true }, (_eventType, filename) => {
    if (!filename) return;
    const full = path.join(inboxDir, filename);
    setTimeout(() => { if (fs.existsSync(full)) handleFile(full); }, 250);
  });
}

main();
