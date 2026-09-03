'use strict';

const fs = require('fs');
const Module = require('module');
const path = require('path');
const vm = require('vm');

const backendRoot = path.resolve(__dirname, '..');
const sourceRoot = path.join(backendRoot, 'src');
const indexFile = path.join(sourceRoot, 'index.js');

require('dotenv').config({
  path: path.join(backendRoot, '.env'),
  override: true,
});

function listJavaScriptFiles(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) return listJavaScriptFiles(entryPath);
    return entry.isFile() && entry.name.endsWith('.js') ? [entryPath] : [];
  });
}

function relative(filePath) {
  return path.relative(backendRoot, filePath).replaceAll('\\', '/');
}

function checkSyntax(files) {
  const failures = [];

  for (const file of files) {
    try {
      const source = fs.readFileSync(file, 'utf8');
      new vm.Script(Module.wrap(source), { filename: file });
    } catch (error) {
      failures.push({
        file: relative(file),
        output: error.stack || error.message,
      });
    }
  }

  if (failures.length > 0) {
    for (const failure of failures) {
      console.error(`[preflight] Syntax failed: ${failure.file}`);
      console.error(failure.output);
    }
    throw new Error(`${failures.length} JavaScript file(s) failed syntax validation`);
  }
}

function replaceDatabaseWithPreflightStub() {
  const databaseModule = require.resolve(path.join(sourceRoot, 'config', 'db.js'));

  // Load the real database module once to validate its dependencies and setup,
  // then replace only its Pool export before any routes are loaded. Several
  // legacy routes run idempotent schema setup at import time; preflight must
  // never connect to or modify the production database.
  require(databaseModule);

  const emptyResult = Object.freeze({ rows: [], rowCount: 0 });
  const fakeClient = {
    query: async () => emptyResult,
    release: () => {},
  };
  const fakePool = {
    query: async () => emptyResult,
    connect: async () => fakeClient,
    on: () => fakePool,
    end: async () => {},
  };

  require.cache[databaseModule].exports = { pool: fakePool };
}

function indexLocalDependencies() {
  const source = fs.readFileSync(indexFile, 'utf8');
  const literalRequire = /require\(\s*(['"])([^'"]+)\1\s*\)/g;
  const dependencies = [];

  for (const match of source.matchAll(literalRequire)) {
    const request = match[2];
    if (!request.startsWith('.')) continue;
    dependencies.push(require.resolve(path.resolve(path.dirname(indexFile), request)));
  }

  return dependencies;
}

function loadStartupModules() {
  const routeFiles = fs
    .readdirSync(path.join(sourceRoot, 'routes'), { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.js'))
    .map((entry) => path.join(sourceRoot, 'routes', entry.name));

  const modules = [...new Set([...indexLocalDependencies(), ...routeFiles])].sort();

  for (const modulePath of modules) {
    try {
      require(modulePath);
    } catch (error) {
      console.error(`[preflight] Module load failed: ${relative(modulePath)}`);
      throw error;
    }
  }

  return modules.length;
}

try {
  const sourceFiles = listJavaScriptFiles(sourceRoot);
  checkSyntax(sourceFiles);
  process.env.HRMS_PREFLIGHT = '1';
  replaceDatabaseWithPreflightStub();
  const loadedModules = loadStartupModules();

  console.log(
    `[preflight] Passed: ${sourceFiles.length} source files parsed; ${loadedModules} startup modules loaded.`,
  );
} catch (error) {
  console.error(`[preflight] FAILED: ${error.message}`);
  process.exitCode = 1;
}
