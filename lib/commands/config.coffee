path = require 'path'
fs = require 'fs'
homeDir = require 'home-dir'
minimist = require 'minimist'
RSVP = require 'rsvp'
chalk = require 'chalk'
_ = require 'lodash'
help = require './help'


newConfigHashItem = (option, value) ->
  optionsHash = {}
  switch option
    when 'configDir'
      exists = fs.existsSync path.resolve(value)
      if !exists
        process.stdout.write chalk.yellow "Warning: "
        process.stdout.write "#{value} does not exist\n"
      optionsHash[option] = value
    else
      # JSON parse gives us "true" -> true
      optionsHash[option] = JSON.parse(value)
  optionsHash

setConfigOption = (option, value) ->
  new RSVP.Promise (resolve, reject) ->
    galleycfgPath = path.resolve(homeDir(), '.galleycfg')
    existingGalleycfgHash = {}
    exists = fs.existsSync galleycfgPath
    if exists
      process.stdout.write 'Updating ~/.galleycfg\n'
      galleycfg = fs.readFileSync galleycfgPath
      existingGalleycfgHash = JSON.parse galleycfg.toString()
    else
      process.stdout.write 'Creating ~/.galleycfg\n'

    galleycfgHash = _.merge(existingGalleycfgHash, newConfigHashItem option, value)

    fs.writeFile galleycfgPath, JSON.stringify(galleycfgHash, false, 2), (err) ->
      reject err if err
      resolve()

module.exports = (args, options, done) ->
  argv = minimist args,
    boolean: [
      'help'
    ]

  if argv._.length isnt 2 or argv.help
    return help args, options, done

  configPromise = RSVP.resolve()
  if argv['_'][0] == 'set'
    option = argv['_'][1]
    value = argv['_'][2]
    configPromise = configPromise.then ->
      setConfigOption(option, value)

  configPromise
  .then ->
    process.stdout.write chalk.green 'done!\n'
    done?()
  .catch (err) ->
    process.stdout.write chalk.red err
    process.stdout.write chalk.red err.stack
    process.stdout.write chalk.red '\nAborting.\n'
    process.exit 1

