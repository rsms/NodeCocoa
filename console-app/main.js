// export all public members of |sys| to |global|
var sys = require('util');
Object.keys(sys).forEach(function(k){ global[k] = sys[k] });

if (typeof process.stdout === 'number') {
  process.stdout = new require('net').Stream(process.stdout);
  process.stdout.readable = false;
}

console.log('hello from main.js');

// as our demo app is emitting a "keyPress" event, let's listen for it
process.on('keyPress', function () {
  console.log('process.on:keyPress(%s)',
              inspect(Array.prototype.slice.apply(arguments)))
})

// test timeout (should block graceful program termination)
var t = new Date;
setTimeout(function() {
  t = (new Date).getTime() - t.getTime();
  console.log('timeout in main.js after '+t+' ms (expected 4321 ms)');
}, 4321);
