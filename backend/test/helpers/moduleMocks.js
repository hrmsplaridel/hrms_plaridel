const path = require('node:path');

function resolveFromTest(modulePath) {
  if (path.isAbsolute(modulePath)) return require.resolve(modulePath);
  try {
    return require.resolve(modulePath);
  } catch (_) {
    return require.resolve(path.resolve(__dirname, '..', modulePath));
  }
}

function withMockedModule(modulePath, exportsValue) {
  const resolved = resolveFromTest(modulePath);
  const previous = require.cache[resolved];
  require.cache[resolved] = {
    id: resolved,
    filename: resolved,
    loaded: true,
    exports: exportsValue,
  };

  return () => {
    if (previous) {
      require.cache[resolved] = previous;
    } else {
      delete require.cache[resolved];
    }
  };
}

function clearModule(modulePath) {
  delete require.cache[resolveFromTest(modulePath)];
}

module.exports = {
  clearModule,
  withMockedModule,
};
