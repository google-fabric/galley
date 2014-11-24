chokidar = require 'chokidar'

# Separate binary to watch for changes and send a 'change' message back to the parent when they
# happen. We isolate this into its own process because the fsevents code has a habit of segfaulting
# when removing lots of files at once.

DEBOUNCE_INTERVAL_MS = 50

notifyTimeout = null

watchHandler = (path) ->
  clearTimeout(notifyTimeout) if notifyTimeout
  notifyTimeout = setTimeout(notifyHandler, DEBOUNCE_INTERVAL_MS)

notifyHandler = ->
  notifyTimeout = null

  # If the parent process has since died (it was killed in a way that prevented it from cleanly
  # killing us) then this call will raise a "channel closed" exception and terminate us, which is
  # perfectly fine.
  process.send 'change'

source = process.argv[2]
watcher = chokidar.watch source,
  ignored: /\.DS_Store|\.git/
  ignoreInitial: true
.on 'add', watchHandler
.on 'addDir', watchHandler
.on 'change', watchHandler
.on 'unlink', watchHandler
.on 'unlinkDir', watchHandler
