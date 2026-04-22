#!/usr/bin/env node
/**
 * cortex_eyes.js — Cortex visual interface
 *
 * Pokreće HELIX u Chromium i daje Cortexu oči i ruke:
 * - snap: screenshot → /tmp/cortex_snap.png
 * - click x,y: klik na koordinatu + snap
 * - goto url: navigacija
 * - find text: pronađi element po tekstu + info
 * - eval js: izvrši JS i vrati rezultat
 *
 * Usage:
 *   node cortex_eyes.js snap
 *   node cortex_eyes.js click 400,300
 *   node cortex_eyes.js find "HELIX"
 *   node cortex_eyes.js eval "document.title"
 *   node cortex_eyes.js serve   ← pokreće Flutter web + otvara browser
 */

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const { execSync, spawn } = require('child_process');

const SNAP_PATH = '/tmp/cortex_snap.png';
const STATE_FILE = '/tmp/cortex_eyes_state.json';
const FLUTTER_URL = 'http://localhost:8080';

async function getPage() {
  // Reuse existing browser if possible via CDP
  let browser;
  try {
    browser = await chromium.connectOverCDP('http://localhost:9222');
    const contexts = browser.contexts();
    if (contexts.length > 0) {
      const pages = contexts[0].pages();
      if (pages.length > 0) return { browser, page: pages[0], owned: false };
    }
  } catch (e) {
    // No existing browser, launch new
    browser = await chromium.launch({
      headless: false,
      args: [
        '--remote-debugging-port=9222',
        '--window-size=1800,1000',
        '--disable-web-security',
      ],
    });
    const ctx = await browser.newContext({ viewport: { width: 1800, height: 1000 } });
    const page = await ctx.newPage();
    return { browser, page, owned: true };
  }
  // Fallback
  browser = await chromium.launch({
    headless: false,
    args: ['--remote-debugging-port=9222', '--window-size=1800,1000'],
  });
  const ctx = await browser.newContext({ viewport: { width: 1800, height: 1000 } });
  const page = await ctx.newPage();
  return { browser, page, owned: true };
}

async function snap(page) {
  await page.screenshot({ path: SNAP_PATH, fullPage: false });
  console.log(SNAP_PATH);
}

async function main() {
  const cmd = process.argv[2] || 'snap';
  const arg = process.argv[3] || '';
  const arg2 = process.argv[4] || '';

  if (cmd === 'serve') {
    // Start Flutter web server and open browser
    console.log('Starting Flutter web server...');
    const flutter = spawn('flutter', ['run', '-d', 'chrome', '--web-port=8080'], {
      cwd: '/Users/vanvinklstudio/Projects/fluxforge-studio/flutter_ui',
      detached: true,
      stdio: 'ignore',
    });
    flutter.unref();
    console.log(`Flutter web starting on ${FLUTTER_URL}`);
    console.log('Wait ~10s then run: node cortex_eyes.js snap');
    return;
  }

  if (cmd === 'help') {
    console.log(`
cortex_eyes — Cortex visual interface

Commands:
  snap              - Screenshot → /tmp/cortex_snap.png
  click x,y         - Click at coordinates + screenshot
  dclick x,y        - Double click + screenshot
  move x,y          - Move mouse to coordinates
  type text         - Type text + screenshot
  goto url          - Navigate to URL + screenshot
  find "text"       - Find element by text, return bounding box
  eval "js"         - Execute JavaScript, return result
  wait ms           - Wait N milliseconds
  scroll x,y dir    - Scroll at position (up/down)
  open url          - Open URL in new browser window
  serve             - Start Flutter web + open browser

Output: always prints path to screenshot file
    `);
    return;
  }

  const { browser, page, owned } = await getPage();

  try {
    switch (cmd) {
      case 'snap':
        if (owned) await page.goto(FLUTTER_URL, { waitUntil: 'networkidle', timeout: 15000 }).catch(() => {});
        await snap(page);
        break;

      case 'click': {
        const [x, y] = arg.split(',').map(Number);
        await page.mouse.click(x, y);
        await page.waitForTimeout(400);
        await snap(page);
        break;
      }

      case 'dclick': {
        const [x, y] = arg.split(',').map(Number);
        await page.mouse.dblclick(x, y);
        await page.waitForTimeout(400);
        await snap(page);
        break;
      }

      case 'move': {
        const [x, y] = arg.split(',').map(Number);
        await page.mouse.move(x, y);
        await snap(page);
        break;
      }

      case 'type': {
        await page.keyboard.type(arg);
        await page.waitForTimeout(300);
        await snap(page);
        break;
      }

      case 'goto': {
        await page.goto(arg || FLUTTER_URL, { waitUntil: 'networkidle', timeout: 20000 });
        await snap(page);
        break;
      }

      case 'find': {
        // Try to find element by text in DOM
        const result = await page.evaluate((text) => {
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
          let node;
          while ((node = walker.nextNode())) {
            if (node.textContent.toLowerCase().includes(text.toLowerCase())) {
              const rect = node.parentElement.getBoundingClientRect();
              return {
                text: node.textContent.trim(),
                tag: node.parentElement.tagName,
                x: Math.round(rect.x + rect.width / 2),
                y: Math.round(rect.y + rect.height / 2),
                rect: { x: Math.round(rect.x), y: Math.round(rect.y), w: Math.round(rect.width), h: Math.round(rect.height) }
              };
            }
          }
          return null;
        }, arg);
        console.log(JSON.stringify(result, null, 2));
        await snap(page);
        break;
      }

      case 'eval': {
        const result = await page.evaluate(arg);
        console.log('Result:', JSON.stringify(result, null, 2));
        await snap(page);
        break;
      }

      case 'wait': {
        await page.waitForTimeout(parseInt(arg) || 1000);
        await snap(page);
        break;
      }

      case 'scroll': {
        const [x, y] = arg.split(',').map(Number);
        const dir = arg2 === 'up' ? -300 : 300;
        await page.mouse.move(x, y);
        await page.mouse.wheel(0, dir);
        await page.waitForTimeout(300);
        await snap(page);
        break;
      }

      case 'open': {
        await page.goto(arg || FLUTTER_URL, { timeout: 20000 });
        await page.waitForTimeout(2000);
        await snap(page);
        break;
      }

      case 'key': {
        await page.keyboard.press(arg);
        await page.waitForTimeout(200);
        await snap(page);
        break;
      }

      default:
        console.error(`Unknown command: ${cmd}`);
        process.exit(1);
    }
  } finally {
    if (owned) {
      // Keep browser open, just disconnect
      // await browser.close();
    }
  }
}

main().catch((err) => {
  console.error('cortex_eyes error:', err.message);
  process.exit(1);
});
