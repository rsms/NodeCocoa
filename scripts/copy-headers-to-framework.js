#!/usr/bin/env node
var fs = require('fs'), verbose = false;

if (!('PUBLIC_HEADERS_FOLDER_PATH' in process.env)) {
  // not running from Xcode
  process.env['TARGET_BUILD_DIR'] =
      require('path').dirname(__dirname)+'/build/Debug';
  process.env['PUBLIC_HEADERS_FOLDER_PATH'] =
      'NodeJS.framework/Versions/A/Headers';
  verbose = true;
}

var dirname = process.env['TARGET_BUILD_DIR']+'/'+
              process.env['PUBLIC_HEADERS_FOLDER_PATH'];

if (verbose) console.log('entering directory '+dirname);

var headers = fs.readdirSync(dirname).filter(function (filename) {
  return (/\.h$/).test(filename);
}).sort();

RegExp.escape = function(text) {
  if (!arguments.callee.sRE) {
    var specials = [
      '/', '.', '*', '+', '?', '|',
      '(', ')', '[', ']', '{', '}', '\\'
    ];
    arguments.callee.sRE = new RegExp(
      '(\\' + specials.join('|\\') + ')', 'g'
    );
  }
  return text.replace(arguments.callee.sRE, '\\$1');
}

var patterns = [];
headers.forEach(function (filename) {
  patterns.push([
    new RegExp('#(include|import) <'+RegExp.escape(filename)+'>', 'g'),
    '#$1 <NodeCocoa/'+filename+'>'
  ]);
});

headers.forEach(function (filename) {
  var path = dirname+'/'+filename;
  var buf = fs.readFileSync(path, 'utf8'), origBuf = buf;
  patterns.forEach(function (t) {
    buf = buf.replace(t[0], t[1]);
  });
  if (buf !== origBuf) {
    fs.writeFileSync(path, buf, 'utf8');
    if (verbose) console.log(filename+' written');
  } else if (verbose) {
    console.log(filename+' not modified');
  }
});
