'use strict';
/**
 * Employee DocuTracker capture @ 1440x900.
 * Seeds SharedPreferences tutorial flags so DocuTracker opens without coach overlay.
 * After OS login sets _employee_ready.flag, navigates and shoots.
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
const LOGIN_READY = path.join(__dirname, '_employee_ready.flag');
const TOUR_SKIPPED = path.join(__dirname, '_emp_tour_skipped.flag');
const STOP = path.join(__dirname, '_employee_done.flag');

/** Dann Zapitan employee id (from /auth/login). */
const EMP_USER_ID = 'de7161b5-5411-4c17-bfdd-90bd34cbfd2c';

fs.mkdirSync(OUT, { recursive: true });
for (const f of [LOGIN_READY, TOUR_SKIPPED, STOP]) {
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

async function waitFile(file, timeoutMs) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (fs.existsSync(file)) return true;
    await new Promise((r) => setTimeout(r, 300));
  }
  return false;
}

async function seedTutorialPrefs(page) {
  await page.evaluate((uid) => {
    const sections = [
      'dashboard',
      'attendance',
      'leave',
      'locator',
      'trainingReports',
      'trainingRequirements',
      'docuTracker',
      'profileSettings',
    ];
    for (const s of sections) {
      const key = `flutter.employee_tutorial_v2:${uid}:${s}`;
      localStorage.setItem(key, 'true');
      // some shared_preferences builds also keep a JSON bag
      try {
        const bagKey = 'flutter.shared_preferences';
        const raw = localStorage.getItem(bagKey);
        const bag = raw ? JSON.parse(raw) : {};
        bag[`employee_tutorial_v2:${uid}:${s}`] = true;
        localStorage.setItem(bagKey, JSON.stringify(bag));
      } catch (_) {}
    }
  }, EMP_USER_ID);
  console.log('seeded tutorial prefs');
}

async function skipTourClicks(page) {
  for (const [x, y] of [
    [1320, 95],
    [1280, 90],
    [1220, 720],
    [1100, 700],
  ]) {
    await page.mouse.click(x, y, { delay: 40 });
    await idle(page, 300);
  }
  for (let i = 0; i < 3; i++) {
    await page.keyboard.press('Escape');
    await idle(page, 200);
  }
}

async function goDocuTracker(page) {
  await page.mouse.click(160, 400, { delay: 90 });
  await idle(page, 2800);
  await skipTourClicks(page);
  await idle(page, 800);
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
  await idle(page, 4000);
  await seedTutorialPrefs(page);
  console.log('LOGIN_PAGE_READY');
  console.log('FLAG', LOGIN_READY);

  if (!(await waitFile(LOGIN_READY, 420000))) {
    console.error('login timeout');
    await browser.close();
    process.exit(1);
  }

  console.log('FLAG_SEEN — capturing');
  await idle(page, 2000);
  // Re-seed after login in case auth wiped nothing but prefs load order matters
  await seedTutorialPrefs(page);
  await skipTourClicks(page);
  await shot(page, 'employee_00_after_login.png');
  await shot(page, 'employee_01_home.png');

  await page.mouse.wheel(0, 750);
  await idle(page, 1200);
  await shot(page, 'employee_04_my_documents_dashboard.png');
  await page.mouse.wheel(0, -950);
  await idle(page, 700);

  await goDocuTracker(page);

  // Optional OS assist: wait briefly for manual Skip if overlay still present
  console.log('DOCUTRACKER_OPEN — waiting optional tour skip flag (45s)');
  console.log('FLAG', TOUR_SKIPPED);
  await waitFile(TOUR_SKIPPED, 45000);
  await skipTourClicks(page);
  await idle(page, 1000);

  await shot(page, 'employee_02_documents.png');

  // Required actions DocuTracker chip
  await page.mouse.click(480, 250, { delay: 70 });
  await idle(page, 1000);
  await shot(page, 'employee_03_required_actions.png');

  // Create Draft ~ (1306, 706)
  await page.mouse.click(1306, 706, { delay: 100 });
  await idle(page, 2000);
  await shot(page, 'employee_05_create_draft.png');
  await page.keyboard.press('Escape');
  await idle(page, 800);

  // Open first required-action card
  await page.mouse.click(420, 340, { delay: 90 });
  await idle(page, 3200);
  await shot(page, 'employee_06_document_detail.png');
  await page.mouse.wheel(0, 520);
  await idle(page, 1100);
  await shot(page, 'employee_07_workflow.png');
  await page.mouse.wheel(0, 480);
  await idle(page, 1000);
  await shot(page, 'employee_09_activity.png');

  await page.keyboard.press('Escape');
  await idle(page, 600);
  await page.mouse.click(48, 88, { delay: 60 });
  await idle(page, 1200);
  await goDocuTracker(page);

  await page.mouse.click(1360, 34, { delay: 70 });
  await idle(page, 1600);
  await shot(page, 'employee_08_notifications.png');
  await page.keyboard.press('Escape');
  await idle(page, 700);

  await page.mouse.click(1100, 700, { delay: 90 });
  await idle(page, 2200);
  await shot(page, 'employee_10_my_signatures.png');

  fs.writeFileSync(STOP, 'ok');
  console.log('batch-done');
  await idle(page, 1000);
  await browser.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
