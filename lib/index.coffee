path = require 'path'
fs = require 'fs'
_ = require 'lodash'
chalk = require 'chalk'
homeDir = require 'home-dir'
minimist = require 'minimist'

commands =
  pull: require './commands/pull'
  'stop-env': require './commands/stop_env'
  cleanup: require './commands/cleanup'
  run: require './commands/run'

  help: require './commands/help'
  version: require './commands/version'
  config: require './commands/config'

loadGlobalOptionsSync = ->
  globalConfigPath = path.resolve(homeDir(), '.galleycfg')
  if fs.existsSync(globalConfigPath)
    JSON.parse fs.readFileSync(globalConfigPath, { encoding: 'utf-8' })
  else
    {}

printHelp = (prefix) ->
  commands.help [], prefix: prefix

runCommand = (prefix, args, commands, opts) ->
  argv = minimist args,
    boolean: ['help']

  if argv['help']
    printHelp argv._

  else unless args.length
    printHelp []
    process.exit 1

  else if (command = commands[args[0]])?
    try
      commandOpts = _.merge {}, opts,
        prefix: [args[0]]

      command args.slice(1), commandOpts, (statusCode = 0) -> process.exit statusCode
    catch err
      if typeof err is 'string'
        process.stdout.write chalk.red err
      else
        process.stdout.write err?.stack

      process.stdout.write chalk.red '\nAborting\n'
      process.exit -1

  else
    console.log "Error: Command not found: #{args[0]}"
    printHelp []
    process.exit 1

run = (galleyfilePath, argv) ->
  # Convert SIGTERM and SIGINT directly into exits so that we can listen for 'exit' events to shut
  # down our child watcher process.
  sigHandler = -> process.exit(0)
  process.once 'SIGTERM', sigHandler
  process.once 'SIGINT', sigHandler

  opts =
    config: require galleyfilePath
    globalOptions: loadGlobalOptionsSync()

  args = process.argv.slice 2
  runCommand [], args, commands, opts

module.exports = run
