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
const CREDS = path.join(process.env.TEMP || '.', 'hrms_shot_creds.json');
const BASE = 'http://127.0.0.1:5000/';
fs.mkdirSync(OUT, { recursive: true });

async function idle(page, ms = 800) {
  await page.waitForTimeout(ms);
}

async function shot(page, name) {
  const file = path.join(OUT, name);
  await page.screenshot({ path: file, type: 'png' });
  console.log('saved', name);
}

async function fillLogin(page, email, password) {
  await idle(page, 4000);
  // Email field (right card)
  await page.mouse.click(1100, 470, { delay: 60 });
  await idle(page, 400);
  await page.keyboard.press('Control+A');
  await page.keyboard.type(email, { delay: 25 });
  await idle(page, 300);
  // Password
  await page.mouse.click(1100, 555, { delay: 60 });
  await idle(page, 400);
  await page.keyboard.type(password, { delay: 25 });
  await idle(page, 300);
  // Sign In
  await page.mouse.click(1100, 680, { delay: 80 });
  await idle(page, 6000);
}

async function goDocuTracker(page) {
  await page.mouse.click(140, 550, { delay: 80 });
  await idle(page, 2800);
}

async function runAdmin(browser, email, password) {
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 120000 });
  await fillLogin(page, email, password);
  await shot(page, 'admin_00_after_login.png');

  // DocuTracker overview lives on admin dashboard below recruitment
  await page.mouse.wheel(0, 1000);
  await idle(page, 1500);
  await shot(page, 'admin_01_dashboard.png');

  await goDocuTracker(page);
  await shot(page, 'admin_02_documents.png');

  // DocuTracker required-actions chip
  await page.mouse.click(612, 396, { delay: 80 });
  await idle(page, 1200);
  await shot(page, 'admin_03_required_actions.png');

  // Create Draft
  await page.mouse.wheel(0, 450);
  await idle(page, 700);
  await page.mouse.click(1302, 580, { delay: 120 });
  await idle(page, 1800);
  await shot(page, 'admin_04_create_draft.png');
  await page.keyboard.press('Escape');
  await idle(page, 800);

  // Open a list row
  await page.mouse.click(700, 760, { delay: 100 });
  await idle(page, 2800);
  await shot(page, 'admin_05_document_detail.png');
  await page.mouse.wheel(0, 520);
  await idle(page, 900);
  await shot(page, 'admin_06_workflow_progress.png');
  await page.mouse.wheel(0, 520);
  await idle(page, 900);
  await shot(page, 'admin_07_activity_trail.png');

  // Notifications
  await page.mouse.click(1388, 34, { delay: 80 });
  await idle(page, 1400);
  await shot(page, 'admin_08_notifications.png');
  await page.keyboard.press('Escape');
  await idle(page, 700);

  // Admin workflows
  await goDocuTracker(page);
  await page.mouse.click(520, 227, { delay: 80 });
  await idle(page, 1800);
  await shot(page, 'admin_09_workflows.png');

  // More menu then System access
  await page.mouse.click(1189, 290, { delay: 80 });
  await idle(page, 900);
  await shot(page, 'admin_10_more_menu.png');
  await page.mouse.click(1189, 340, { delay: 80 });
  await idle(page, 2200);
  await shot(page, 'admin_11_system_access.png');

  await goDocuTracker(page);
  await page.mouse.click(520, 227, { delay: 80 });
  await idle(page, 1200);
  await page.mouse.click(1189, 290, { delay: 80 });
  await idle(page, 700);
  await page.mouse.click(1189, 380, { delay: 80 });
  await idle(page, 2200);
  await shot(page, 'admin_12_audit_log.png');

  await goDocuTracker(page);
  await page.mouse.click(520, 227, { delay: 80 });
  await idle(page, 1200);
  await page.mouse.click(1189, 290, { delay: 80 });
  await idle(page, 700);
  await page.mouse.click(1189, 420, { delay: 80 });
  await idle(page, 2200);
  await shot(page, 'admin_13_escalation.png');

  await goDocuTracker(page);
  await page.mouse.click(520, 227, { delay: 80 });
  await idle(page, 1200);
  await page.mouse.click(1189, 290, { delay: 80 });
  await idle(page, 700);
  await page.mouse.click(1189, 460, { delay: 80 });
  await idle(page, 2200);
  await shot(page, 'admin_14_official_signatories.png');

  await goDocuTracker(page);
  await page.mouse.click(520, 227, { delay: 80 });
  await idle(page, 1500);
  await page.mouse.wheel(0, 280);
  await idle(page, 700);
  await page.mouse.click(1280, 520, { delay: 100 });
  await idle(page, 2800);
  await shot(page, 'admin_15_workflow_editor.png');

  await context.close();
}

async function runEmployee(browser, email, password) {
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 120000 });
  await fillLogin(page, email, password);
  await shot(page, 'employee_00_after_login.png');
  await shot(page, 'employee_01_home.png');

  await page.mouse.wheel(0, 800);
  await idle(page, 1200);
  await shot(page, 'employee_04_my_documents_dashboard.png');

  await goDocuTracker(page);
  await shot(page, 'employee_02_documents.png');
  await page.mouse.click(612, 396, { delay: 80 });
  await idle(page, 1200);
  await shot(page, 'employee_03_required_actions.png');

  await page.mouse.wheel(0, 450);
  await idle(page, 700);
  await page.mouse.click(1302, 580, { delay: 120 });
  await idle(page, 1600);
  await shot(page, 'employee_05_create_draft.png');
  await page.keyboard.press('Escape');
  await idle(page, 700);

  await page.mouse.click(700, 760, { delay: 100 });
  await idle(page, 2500);
  await shot(page, 'employee_06_document_detail.png');
  await page.mouse.wheel(0, 480);
  await idle(page, 900);
  await shot(page, 'employee_07_workflow.png');

  await page.mouse.click(1388, 34, { delay: 80 });
  await idle(page, 1400);
  await shot(page, 'employee_08_notifications.png');

  await context.close();
}

(async () => {
  const creds = JSON.parse(fs.readFileSync(CREDS, 'utf8'));
  const browser = await chromium.launch({ headless: true });
  try {
    await runAdmin(browser, creds.adminEmail, creds.password);
    await runEmployee(browser, creds.employeeEmail, creds.password);
    console.log('batch-done');
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
