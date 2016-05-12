_ = require 'lodash'
child_process = require 'child_process'
chokidar = require 'chokidar'
fs = require 'fs'
path = require 'path'
RSVP = require 'rsvp'
Rsync = require('rsync')

WATCH_CHILD_PATH = path.resolve __dirname, '../bin/watch.js'

# Class to watch a directory for changes and use rsync to bring a remote directory up-to-date.
class Rsyncer
  # Options:
  #  src: full local path to a directory to watch and sync
  #  dest: remote path to sync to
  #  host: remote server running Rsync daemon
  #  port: port Rsync is running on
  #  module: remote module on the server
  constructor: (options) ->
    @source = options.src

    # True if an rsync process is currently running on our behalf
    @syncing = false

    # True if, after the current rsync process completes we should immediately kick off another
    # one because files may have changed in the meantime.
    @needsResync = false

    # True if there's a watch child process running.
    @watching = false
    @watchChild = null

    # Callback for us to send change / sync / waiting activity to. Set in the call to watch.
    @activityCb = null

    @rsync = Rsync.build
      source: "#{options.src}/"
      destination: "rsync://#{options.host}:#{options.port}/#{options.module}#{options.dest}/"
      flags: 'av'
    .set 'delete'

    # .dockerignore is a pretty good set of files not to bother to sync
    dockerignorePath = path.resolve(options.src, '.dockerignore')
    if fs.existsSync(dockerignorePath)
      @rsync.set 'exclude-from', dockerignorePath

  # Syncs the local "src" to "dest". progressCb is called periodically with arrays of file paths
  # as rsync reports them being synced.
  #
  # Returns a promise that resolves to the list of files synched.
  sync: (progressCb) ->
    new RSVP.Promise (resolve, reject) =>
      statusLines = []
      @syncing = true

      completionHandler = (error, code, cmd) =>
        @syncing = false

        # First 2 lines are about synchronizing files list and being done. Last lines are a summary
        # of the number of bytes transferred. Clear them both out to leave the list of files.
        # Additionally filter to remove lines just about directories.
        pathStatusLines = statusLines[2...-2]
        fileStatusLines = _.filter pathStatusLines, (line) -> line.slice(-1) isnt '/'

        if error then reject(error)
        else resolve(fileStatusLines)

      # "data" ends up being some chunk of rsync's output, which is for the most part newline-
      # separated file paths.
      stdoutHandler = (data) ->
        newStatusLines = _.filter data.toString().split('\n'), (line) -> line isnt ''
        statusLines = statusLines.concat newStatusLines
        progressCb(newStatusLines)

      @rsync.execute completionHandler, stdoutHandler

  # Cause a sync to occur. We assume that this is called at a reasonably debounced interval. If
  # called while the sync is already in progress, schedules a resync to occur right after that sync
  # completes to pick up the additional changes. The resync's result is collapsed into the original
  # sync's result.
  #
  # If no sync is going on, returns a promise that will resolve to a list of files synched,
  # including any files from later resyncs.
  #
  # If a sync is currently going on, returns undefined.
  scheduleSync: (progressCb, accumFiles = []) ->
    if @syncing
      @needsResync = true
      return

    syncPromise = @sync(progressCb)
    .then (newFiles) =>
      accumFiles.push.apply accumFiles, newFiles

      if @needsResync
        @needsResync = false
        @scheduleSync progressCb, accumFiles
      else
        accumFiles

  # Called to watch the "src" directory provided to the constructor and run rsync if its contents
  # change.
  #
  # Calls the activityCb with an event, the watched path, a list of files (or null), and an error
  # (or null)
  #  'watching': Rsyncer is waiting for the directory to change. Called right after watch is called
  #    and again after every sync has completed.
  #  'changed': A change has been detected and a sync will be kicked off. Not called if additional
  #    changes are detected during a sync, as the scheduleSync method will roll those in to the
  #    same rsync call.
  #  'synching': A sync is in progress, and rsync is writing changed file paths to stdout.
  #  'synched': A sync has just completed. Includes the list of file paths that rsync reported
  #    changing as the 3rd argument.
  #  'error': Something unfortunate happend. Includes the caught error as the 4th argument.
  watch: (@activityCb = ->) ->
    # For consistency, schedule this callback to happen soon rather than during the initial call
    # to watch.
    process.nextTick @activityCb.bind(null, 'watching', @source, null, null)

    @startWatchChild()

    # We need to make sure to stop the child when we exit. Pattern of binding to SIGINT and
    # SIGTERM (found in the galley binary) and to uncaughtException courtesy of:
    # https://www.exratione.com/2013/05/die-child-process-die/
    process.once 'exit', @stop.bind @
    process.once 'uncaughtException', (error) =>
      if process.listeners('uncaughtException').length is 0
        @stop()
        throw error

  # Since fsevents can get a bit segfaulty, we isolate the watching into a child process so that
  # it can crash without bringing down all of Galley.
  startWatchChild: ->
    @watching = true
    @watchChild = child_process.fork WATCH_CHILD_PATH, [@source], silent: true

    @watchChild.on 'message', (msg) =>
      switch msg
        when 'change' then @receivedChange()

    # Triggered when either we are exiting the child (in which case @watching will be false) or
    # when the process crashes. If it crashes, we restart it, but also treat it as a "change" event
    # since file system changes are what would cause it to crash.
    @watchChild.on 'exit', =>
      return unless @watching

      # TODO(finneganh): Maybe detect crash loop?
      @startWatchChild()
      @receivedChange()

  receivedChange: ->
    syncPromise = @scheduleSync @activityCb.bind(null, 'syncing', @source, null, null)

    if syncPromise
      @activityCb('changed', @source, null, null)

      syncPromise
      .then (files) =>
        @activityCb('synched', @source, files, null)
        @activityCb('watching', @source, null, null)
      .catch (err) =>
        @activityCb('error', @source, null, err)

  stop: ->
    @watching = false
    @watchChild?.kill 'SIGTERM'
    @watchChild = null
    @activityCb = null

module.exports = Rsyncer
