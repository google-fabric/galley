_ = require 'lodash'
chokidar = require 'chokidar'
fs = require 'fs'
path = require 'path'

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

# If a .dockerignore exists, respect its ignored files including the default ignored
ignoredFilesList = ['.DS_Store', '.git']
dockerignorePath = path.resolve(source, '.dockerignore')
if fs.existsSync(dockerignorePath)
  dockerignoreLines = fs.readFileSync(dockerignorePath).split('\n')
  ignoredFilesList = _.concat(ignoredFilesList, dockerignoreLines)

ignoredFilesList = _.map(ignoredFilesList, (line) ->
  line.replace('.', '\\.')
)
ignoredFilesRegex = '/' + ignoredFilesList.join('|') + '/'

watcher = chokidar.watch source,
  ignored: ignoredFilesRegex
  ignoreInitial: true
.on 'add', watchHandler
.on 'addDir', watchHandler
.on 'change', watchHandler
.on 'unlink', watchHandler
.on 'unlinkDir', watchHandler
