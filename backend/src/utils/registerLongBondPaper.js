const { execFile } = require('child_process');
const path = require('path');

/**
 * Best-effort: register Windows form "8.5 x 13" so it can appear in the
 * system print dialog. Chrome's own paper list cannot be modified by the app.
 */
function registerLongBondPaperForm() {
  if (process.platform !== 'win32') return;
  const script = path.join(__dirname, '../../scripts/add-long-bond-paper.ps1');
  execFile(
    'powershell.exe',
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script],
    { windowsHide: true, timeout: 15000 },
    (err, stdout, stderr) => {
      const out = String(stdout || '').trim();
      const fail = String(stderr || '').trim();
      if (err) {
        console.warn(
          '[paper] Could not register 8.5 x 13 form (run backend/scripts/add-long-bond-paper.ps1 as Administrator if needed).',
          err.message || fail || out,
        );
        return;
      }
      if (out) console.log(`[paper] ${out}`);
    },
  );
}

module.exports = { registerLongBondPaperForm };
