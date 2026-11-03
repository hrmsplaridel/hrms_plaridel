'use strict';
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
const EMAIL = 'dzapitan@gmail.com';
const PASSWORD = 'admin123';

fs.mkdirSync(OUT, { recursive: true });

async function idle(page, ms = 800) {
  await page.waitForTimeout(ms);
}

async function shot(page, name) {
  await page.screenshot({ path: path.join(OUT, name), type: 'png' });
  console.log('saved', name);
}

async function login(page) {
  await idle(page, 5000);
  // Email
  await page.mouse.click(1100, 470, { delay: 80 });
  await idle(page, 500);
  await page.keyboard.press('Control+A');
  await idle(page, 150);
  await page.keyboard.type(EMAIL, { delay: 40 });
  await idle(page, 400);
  // Password
  await page.mouse.click(1100, 555, { delay: 80 });
  await idle(page, 500);
  await page.keyboard.type(PASSWORD, { delay: 40 });
  await idle(page, 400);
  // Sign in button
  await page.mouse.click(1100, 680, { delay: 100 });
  await idle(page, 8000);
}

(async () => {
  const browser = await chromium.launch({
    headless: false,
    args: ['--window-size=1440,900'],
  });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 120000 });
  await login(page);
  await shot(page, 'employee_00_after_login.png');

  // Home / portal
  await shot(page, 'employee_01_home.png');

  // Scroll for embedded My documents / DocuTracker dashboard if on home
  await page.mouse.wheel(0, 900);
  await idle(page, 1500);
  await shot(page, 'employee_04_my_documents_dashboard.png');

  // Open DocuTracker from sidebar
  await page.mouse.click(140, 550, { delay: 100 });
  await idle(page, 3000);
  await shot(page, 'employee_02_documents.png');

  // Required actions DocuTracker chip
  await page.mouse.click(612, 396, { delay: 80 });
  await idle(page, 1400);
  await shot(page, 'employee_03_required_actions.png');

  // Create draft
  await page.mouse.wheel(0, 450);
  await idle(page, 700);
  await page.mouse.click(1302, 580, { delay: 120 });
  await idle(page, 1800);
  await shot(page, 'employee_05_create_draft.png');
  await page.keyboard.press('Escape');
  await idle(page, 800);

  // Open a document if present
  await page.mouse.click(700, 760, { delay: 100 });
  await idle(page, 2800);
  await shot(page, 'employee_06_document_detail.png');
  await page.mouse.wheel(0, 500);
  await idle(page, 1000);
  await shot(page, 'employee_07_workflow.png');
  await page.mouse.wheel(0, 450);
  await idle(page, 900);
  await shot(page, 'employee_09_activity.png');

  // Notifications
  await page.mouse.click(1388, 34, { delay: 80 });
  await idle(page, 1400);
  await shot(page, 'employee_08_notifications.png');
  await page.keyboard.press('Escape');
  await idle(page, 600);

  // My Signatures if button visible near toolbar
  await page.mouse.click(1180, 580, { delay: 100 });
  await idle(page, 1800);
  await shot(page, 'employee_10_my_signatures.png');

  console.log('batch-done');
  await browser.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
