'use strict';
/**
 * Employee DocuTracker capture for 1440x900 manuscript shots.
 * Waits for _employee_ready.flag after Flutter canvas login (OS typing).
 */
const fs = require('fs');
const path = require('path');
const { chromium } = require(path.join(
  process.env.TEMP || 'C:/Users/danza/AppData/Local/Temp',
  'pw-shot',
  'node_modules',
  'playwright',
));

const OUT = path.join(__dirname, 'chapter4');
const BASE = 'http://127.0.0.1:5000/';
const READY = path.join(__dirname, '_employee_ready.flag');
const DONE = path.join(__dirname, '_employee_done.flag');

fs.mkdirSync(OUT, { recursive: true });
for (const f of [READY, DONE]) {
  try {
    fs.unlinkSync(f);
  } catch (_) {}
}

async function idle(page, ms = 800) {
  await page.waitForTimeout(ms);
}

async function shot(page, name) {
  await page.screenshot({ path: path.join(OUT, name), type: 'png' });
  console.log('saved', name);
}

async function waitFlag(file, timeoutMs) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (fs.existsSync(file)) return true;
    await new Promise((r) => setTimeout(r, 400));
  }
  return false;
}

(async () => {
  const browser = await chromium.launch({
    headless: false,
    args: ['--window-size=1440,900', '--window-position=20,20'],
  });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 120000 });
  await idle(page, 6000);
  console.log('LOGIN_PAGE_READY');
  console.log('FLAG', READY);

  const ok = await waitFlag(READY, 300000);
  if (!ok) {
    console.error('timeout waiting for ready flag');
    await shot(page, 'employee_00_after_login.png');
    await browser.close();
    process.exit(1);
  }

  console.log('FLAG_SEEN — capturing');
  await idle(page, 2000);
  await shot(page, 'employee_00_after_login.png');
  await shot(page, 'employee_01_home.png');

  // DocuTracker in employee sidebar
  await page.mouse.click(130, 545, { delay: 80 });
  await idle(page, 4000);
  await shot(page, 'employee_02_documents.png');
  await shot(page, 'employee_04_my_documents_dashboard.png');

  // Required actions area / DocuTracker chip
  await page.mouse.click(520, 250, { delay: 60 });
  await idle(page, 1500);
  await shot(page, 'employee_03_required_actions.png');

  // My Signatures
  await page.mouse.click(1180, 620, { delay: 80 });
  await idle(page, 2200);
  await shot(page, 'employee_10_my_signatures.png');
  await page.keyboard.press('Escape');
  await idle(page, 900);

  // Create Draft
  await page.mouse.click(1320, 620, { delay: 80 });
  await idle(page, 2200);
  await shot(page, 'employee_05_create_draft.png');
  await page.keyboard.press('Escape');
  await idle(page, 900);

  // Open a required-action card
  await page.mouse.click(420, 360, { delay: 80 });
  await idle(page, 3200);
  await shot(page, 'employee_06_document_detail.png');
  await page.mouse.wheel(0, 500);
  await idle(page, 1100);
  await shot(page, 'employee_07_workflow.png');
  await page.mouse.wheel(0, 450);
  await idle(page, 1000);
  await shot(page, 'employee_09_activity.png');

  // Notifications
  await page.mouse.click(1388, 34, { delay: 60 });
  await idle(page, 1600);
  await shot(page, 'employee_08_notifications.png');

  fs.writeFileSync(DONE, 'ok');
  console.log('batch-done');
  await idle(page, 1500);
  await browser.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
