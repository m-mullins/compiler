const bmanager = require('bin-manager');
const path = require('path');

const packageInfo = require(path.join(__dirname, 'package.json'));
// Use major.minor.patch from version string - e.g. "1.2.3" from "1.2.3-alpha"
// TODO lets do normal versioning
const binVersion = packageInfo.version.replace(/\-/, '.');

const binPath = path.join(__dirname, 'bin', 'elm');


const base = 'https://github.com/m-mullins/compiler/releases/download/' +
        binVersion + '/binary-for-';
const bin = bmanager('bin')
  .src(base + 'mac.tar.gz', 'darwin')
  .src(base + 'linux.tar.gz', 'linux', 'x64')
  .src(base + 'win.tar.gz', 'win32', 'x64')
  .use(process.platform === 'win32' ? 'elm.exe' : 'elm');
 
bin.unload([], () => {
  bin.run(['--version'],  (err, out) => {
    if (err) {
      if (err.stderr) {
          process.stderr.write(err.stderr);
      } else {
          console.error(err);
      }
      return;
    }
    process.stderr.write(out.stderr);
    process.stdout.write(out.stdout);
  });
});
