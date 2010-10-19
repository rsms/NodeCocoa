
// process.host is created by NodeThread
if (process.host) {
  // Curry process.host with extended EventEmitter methods
  Object.keys(process.EventEmitter.prototype).forEach(function(key){
    if (!process.host[key])
      process.host.__proto__[key] = process.EventEmitter.prototype[key];
  });

  process.host.recv = function (what, args) {
    console.log('recv: '+require('sys').inspect({what:what, args:args}));
    var fun = process.host[what];
    return fun.apply(process.host, Array.isArray(args) ? args : []);
  }

  // example
  process.host.readFile = function (filename, callback) {
    require('fs').readFile(filename, callback);
  }

  process.host.on('tabCreated', function (tab) {
    console.log("A tab was created (%j)", tab);
  })
  process.host.on('tabSelected', function (tab) {
    console.log("A tab was selected (%j)", tab);
  })
  process.host.on('tabDetached', function (tab) {
    console.log("A tab was detached (%j)", tab);
  })
  process.host.on('tabClosed', function (tab) {
    console.log("A tab was closed (%j)", tab);
  })

  console.log("process.host = %j", process.host);
} else {
  // Running as stand-alone process
  
}
