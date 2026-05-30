const { spawnSync } = require('child_process');
const { join } = require('path');

const dir = __dirname;

function runNode(script) {
  const result = spawnSync(process.execPath, [join(dir, script)], {
    cwd: dir,
    stdio: 'inherit',
  });
  if (result.status !== 0) {
    process.exit(result.status || 1);
  }
}

runNode('rules-emulator-test.js');
runNode('live-firestore-test.js');
console.log('PASS smoke-test: all enabled checks completed');
