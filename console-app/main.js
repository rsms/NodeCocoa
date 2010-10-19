if (typeof process.stdout === 'number') {
  process.stdout = new require('net').Stream(process.stdout);
  process.stdout.readable = false;
}

var sys = require('sys');
sys.error('hello from main.js');

var t = new Date;
setTimeout(function() {
  t = (new Date).getTime() - t.getTime();
  sys.error('timeout in main.js after '+t+' ms (expected 1234 ms)');
}, 11234);
