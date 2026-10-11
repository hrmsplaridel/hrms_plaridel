function boundedSetting(value, fallback, min, max) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= min && parsed <= max ? parsed : fallback;
}

function busyError() {
  return Object.assign(new Error('Report/PDF processing is busy. Please try again in 5 seconds.'), {
    code: 'HEAVY_OPERATION_BUSY', status: 503, retryAfterSeconds: 5,
  });
}
function abortedError() {
  return Object.assign(new Error('Request disconnected'), {code: 'HEAVY_OPERATION_ABORTED'});
}

function createHeavyWorkQueue({concurrency = 2, maxQueue = 4, waitMs = 5000} = {}) {
  if (!Number.isInteger(concurrency) || concurrency < 1 ||
      !Number.isInteger(maxQueue) || maxQueue < 0 ||
      !Number.isInteger(waitMs) || waitMs < 1) throw new Error('Invalid heavy work queue settings');
  let active = 0;
  const waiting = [];
  function lease() {
    active++;
    let released = false;
    return () => {
      if (released) return;
      released = true;
      active--;
      while (active < concurrency && waiting.length) {
        const next = waiting.shift();
        next.cleanup();
        next.resolve(lease());
      }
    };
  }
  function acquire(signal) {
    if (signal?.aborted) return Promise.reject(abortedError());
    if (active < concurrency) return Promise.resolve(lease());
    if (waiting.length >= maxQueue) return Promise.reject(busyError());
    return new Promise((resolve, reject) => {
      const entry = {resolve, cleanup};
      const timer = setTimeout(() => remove(busyError()), waitMs);
      function abort() { remove(abortedError()); }
      function cleanup() { clearTimeout(timer); signal?.removeEventListener('abort', abort); }
      function remove(error) {
        const index = waiting.indexOf(entry);
        if (index < 0) return;
        waiting.splice(index, 1);
        cleanup();
        reject(error);
      }
      waiting.push(entry);
      signal?.addEventListener('abort', abort, {once: true});
    });
  }
  return {
    async run(work, {signal} = {}) {
      const release = await acquire(signal);
      try {
        if (signal?.aborted) throw abortedError();
        return await work();
      } finally {
        // A disconnected running job still occupies its slot until its work settles.
        release();
      }
    },
  };
}

// One shared queue per backend process for bulk reports and both PDF families.
const heavyWorkQueue = createHeavyWorkQueue({
  concurrency: boundedSetting(process.env.HEAVY_WORK_CONCURRENCY, 2, 1, 16),
  maxQueue: boundedSetting(process.env.HEAVY_WORK_QUEUE_MAX, 4, 0, 100),
  waitMs: boundedSetting(process.env.HEAVY_WORK_QUEUE_WAIT_MS, 5000, 1, 30000),
});
const dtrRowConcurrency = boundedSetting(process.env.DTR_ROW_CONCURRENCY, 4, 1, 16);

async function mapConcurrent(items, concurrency, map) {
  if (!Number.isInteger(concurrency) || concurrency < 1) throw new Error('Invalid row concurrency');
  const output = new Array(items.length);
  let next = 0;
  let failure;
  let failed = false;
  async function worker() {
    while (!failed && next < items.length) {
      const index = next++;
      try { output[index] = await map(items[index], index); }
      catch (error) { if (!failed) failure = error; failed = true; }
    }
  }
  // Drain started work before throwing, so callers cannot release capacity early.
  await Promise.all(Array.from({length: Math.min(concurrency, items.length)}, worker));
  if (failed) throw failure;
  return output;
}

module.exports = {createHeavyWorkQueue, heavyWorkQueue, mapConcurrent, dtrRowConcurrency};
