path = require 'path'
fs = require 'fs'
homeDir = require 'home-dir'
minimist = require 'minimist'
RSVP = require 'rsvp'
chalk = require 'chalk'

setConfigDir = (configDir) ->
  new RSVP.Promise (resolve, reject) ->
    exists = fs.existsSync path.resolve(configDir)
    if !exists
      process.stdout.write chalk.yellow "Warning: "
      process.stdout.write "#{configDir} does not exist\n"

    galleycfgPath = path.resolve(homeDir(), '.galleycfg')
    exists = fs.existsSync galleycfgPath
    if exists
      process.stdout.write 'Updating ~/.galleycfg\n'
      galleycfg = fs.readFileSync galleycfgPath
      galleycfgHash = JSON.parse galleycfg.toString()
      galleycfgHash['configDir'] = configDir
    else
      process.stdout.write 'Creating ~/.galleycfg\n'
      galleycfgHash = configDir: configDir

    fs.writeFile galleycfgPath, JSON.stringify(galleycfgHash, false, 2), (err) ->
      reject err if err
      resolve()

module.exports = (args, options, done) ->
  argv = minimist args

  configPromise = RSVP.resolve()
  if argv['_'][0] == 'set' and argv['_'][1] == 'configDir'
    configPromise = configPromise.then ->
      setConfigDir(argv['_'][2])

  configPromise
  .then ->
    process.stdout.write chalk.green 'done!\n'
    done?()
  .catch (err) ->
    process.stdout.write chalk.red err
    process.stdout.write chalk.red '\nAborting.\n'
    process.exit 1

