// export all public members of |sys| to |global|
var sys = require('sys');
Object.keys(sys).forEach(function(k){ global[k] = sys[k] });

if (typeof process.stdout === 'number') {
  process.stdout = new require('net').Stream(process.stdout);
  process.stdout.readable = false;
}

console.log('hello from main.js');

// test timeout (should block graceful program termination)
var t = new Date;
setTimeout(function() {
  t = (new Date).getTime() - t.getTime();
  console.log('timeout in main.js after '+t+' ms (expected 4321 ms)');
}, 4321);
