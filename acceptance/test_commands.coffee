# Helper to wrap Galley commands (and child_process) in promises to
# better use them with Mocha.

child_process = require 'child_process'
RSVP = require 'rsvp'
stream = require 'stream'
streamBuffers = require 'stream-buffers'

TestReporter = require '../spec/util/test_reporter'

runCommand = require '../lib/commands/run'
stopEnvCommand = require '../lib/commands/stop_env'

GALLEYFILE = require './Galleyfile'

exec = (cmd) ->
  new RSVP.Promise (resolve, reject) ->
    child_process.exec cmd, (err, stdout, stderr) ->
      if err
        reject(err)
      else
        resolve
          stdout: stdout.toString()
          stderr: stderr.toString()

# args is the array of args as would be passed on the command line to "galley run"
#
# runOpts may contain a "stdin" that is used as the contents of stdin for the command.
run = (args, runOpts = {}) ->
  new RSVP.Promise (resolve, reject) ->
    stdin = new stream.Readable
    stdin.push runOpts.stdin or ''
    stdin.push null

    options =
      config: GALLEYFILE
      stdin: stdin
      stdout: new streamBuffers.WritableStreamBuffer(frequency: 0)
      stderr: new streamBuffers.WritableStreamBuffer(frequency: 0)
      reporter: new TestReporter

    runCommand args, options, (statusCode = 0) ->
      if statusCode isnt 0
        reject new Error(options.reporter.lastError or options.stderr.getContentsAsString("utf8"))
      else
        resolve
          reporter: options.reporter
          statusCode: statusCode
          stderr: options.stderr.getContentsAsString("utf8")
          stdout: options.stdout.getContentsAsString("utf8")

stopEnv = (env) ->
  new RSVP.Promise (resolve, reject) ->
    stopEnvCommand [env], {reporter: new TestReporter}, resolve

module.exports = {
  exec
  run
  stopEnv
}