var DEBOUNCE_INTERVAL_MS, chokidar, notifyHandler, notifyTimeout, source, watchHandler, watcher;

chokidar = require('chokidar');

DEBOUNCE_INTERVAL_MS = 50;

notifyTimeout = null;

watchHandler = function(path) {
  if (notifyTimeout) {
    clearTimeout(notifyTimeout);
  }
  return notifyTimeout = setTimeout(notifyHandler, DEBOUNCE_INTERVAL_MS);
};

notifyHandler = function() {
  notifyTimeout = null;
  return process.send('change');
};

source = process.argv[2];

watcher = chokidar.watch(source, {
  ignored: /\.DS_Store|\.git/,
  ignoreInitial: true
}).on('add', watchHandler).on('addDir', watchHandler).on('change', watchHandler).on('unlink', watchHandler).on('unlinkDir', watchHandler);
