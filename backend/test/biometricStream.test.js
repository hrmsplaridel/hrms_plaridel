const test = require('node:test');
const assert = require('node:assert/strict');

function loadFreshBiometricStream() {
  const modulePath = require.resolve('../src/websockets/biometricStream');
  delete require.cache[modulePath];
  return require('../src/websockets/biometricStream');
}

test('initWebSocket returns a reusable server for HTTP upgrade handling', async (t) => {
  const { initWebSocket } = loadFreshBiometricStream();
  const server = initWebSocket();

  t.after(
    () =>
      new Promise((resolve) => {
        server.close(resolve);
      })
  );

  assert.ok(server);
  assert.equal(typeof server.handleUpgrade, 'function');
  assert.equal(initWebSocket(), server);
});
