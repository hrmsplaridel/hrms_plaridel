const fs = require('node:fs');
const path = require('node:path');

function dtrImplementationFiles(directory = path.resolve(__dirname, '../../src/modules/dtr')) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? dtrImplementationFiles(file) : file.endsWith('.js') ? [file] : [];
  });
}

function readDtrImplementation() {
  return dtrImplementationFiles().map((file) => fs.readFileSync(file, 'utf8')).join('\n');
}

module.exports = { dtrImplementationFiles, readDtrImplementation };
