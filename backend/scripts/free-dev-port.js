const { execSync } = require('child_process');
const path = require('path');

require('dotenv').config({
  path: path.resolve(__dirname, '../.env'),
  override: true,
});

const port = Number(process.env.PORT) || 3000;

function freePortOnWindows(targetPort) {
  try {
    const output = execSync(`netstat -ano | findstr :${targetPort}`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'ignore'],
    });

    const pids = new Set();
    for (const line of output.split('\n')) {
      if (!line.includes('LISTENING')) continue;
      const parts = line.trim().split(/\s+/);
      const pid = parts[parts.length - 1];
      if (pid && /^\d+$/.test(pid) && pid !== '0') {
        pids.add(pid);
      }
    }

    for (const pid of pids) {
      try {
        execSync(`taskkill /PID ${pid} /F`, { stdio: 'ignore' });
        console.log(`[dev] Freed port ${targetPort} (stopped PID ${pid})`);
      } catch (_) {
        // Another process may have already released the port.
      }
    }
  } catch (_) {
    // Port is not in use.
  }
}

function freePortOnUnix(targetPort) {
  try {
    execSync(`fuser -k ${targetPort}/tcp`, { stdio: 'ignore' });
    console.log(`[dev] Freed port ${targetPort}`);
  } catch (_) {
    // Port is not in use.
  }
}

if (process.platform === 'win32') {
  freePortOnWindows(port);
} else {
  freePortOnUnix(port);
}
