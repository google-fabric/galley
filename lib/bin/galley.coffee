`#!/usr/bin/env node
'use strict'`

# ------------------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------------------
process.env.INIT_CWD = process.cwd()
failed = false
process.once 'exit', (code) -> process.exit 1 if code is 0 and failed

# ------------------------------------------------------------------------------
# Load in modules
# ------------------------------------------------------------------------------
chalk = require 'chalk'
path = require 'path'
_ = require 'lodash'
fs = require 'fs'
homeDir = require 'home-dir'
Liftoff = require 'liftoff'
minimist = require 'minimist'
RSVP = require 'rsvp'

CoffeeScript = require 'coffee-script'
CoffeeScript.register()

# Convert SIGTERM and SIGINT directly into exits so that we can listen for 'exit' events to shut
# down our child watcher process.
sigHandler = -> process.exit(0)
process.once 'SIGTERM', sigHandler
process.once 'SIGINT', sigHandler

# ------------------------------------------------------------------------------
# Load commands and execute method
# ------------------------------------------------------------------------------
execute = require '../index'

getGalleyConfig = (argv) ->
  configPromise = new RSVP.Promise (resolve, reject) ->
    # no need to pull a search path out of .galleycfg if argument is given on the command line
    if argv['configDir']
      galleyFileLocation = argv['configDir']
    else
      galleyConfig = fs.readFileSync path.resolve(homeDir(), '.galleycfg')
      config = JSON.parse galleyConfig.toString()
      galleyFileLocation = config?['configDir']

    if !galleyFileLocation
      reject("no Galleyfile path provided, either with --configDir or in .galleycfg")

    galleyConfigModule = new Liftoff
      name: 'Galleyfile'
      configName: 'Galleyfile'
      extensions:
        '.js': null
        '.json': null
        '.coffee': 'coffee-script/register'
      searchPaths: [galleyFileLocation]

    galleyConfigModule.launch {}, (env) ->
      if !env.configPath
        err = "Galleyfile not found in #{galleyFileLocation}}"
        if argv['configDir']
          err += ", given with --configDir\n"
        else
          err += ", as defined in ~/.galleycfg\n"
        reject(err)

      config = require path.resolve(env.configPath);
      resolve(config)

printHelp = (prefix) ->
  execute.commands.help [], prefix: prefix

runCommand = (prefix, args, commands) ->
  if typeof commands is 'function'
    argv = minimist args,
      boolean: ['help']

    if argv['help']
      printHelp prefix
    else
      commandPromise = if prefix[0] == 'config'
        RSVP.resolve()
      else
        getGalleyConfig(argv)
      commandPromise
      .then (galleyFile) ->
        opts = 
          prefix: prefix
          config: galleyFile
        commands args, opts, (statusCode = 0) -> process.exit statusCode
      .catch (err) ->
        if typeof err is 'string'
          process.stdout.write chalk.red err
        else
          process.stdout.write err?.stack

        process.stdout.write chalk.red '\nAborting\n'
        process.exit -1

  # Hack to make 'galley service --help' work, which doesn't have a command specified
  else if args[0] == '--help'
    printHelp prefix

  else unless args.length
    printHelp prefix
    process.exit 1

  else if (command = commands[args[0]])?
    prefix.push args[0]
    args = args.slice 1
    runCommand prefix, args, command

  else
    console.log "Error: Command not found: #{args[0]}"
    printHelp prefix
    process.exit 1

# ------------------------------------------------------------------------------
# Run logic
# ------------------------------------------------------------------------------
run = (options) ->
  args = process.argv.slice 2
  runCommand [], args, execute.commands

run {}
