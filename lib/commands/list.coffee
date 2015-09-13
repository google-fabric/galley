_ = require 'lodash'
chalk = require 'chalk'
RSVP = require 'rsvp'

help = require './help'

ServiceHelpers = require '../lib/service_helpers'

listServices = (services) ->
  alphabetizedKeys = _.keys(services)
  alphabetizedKeys.sort()

  for key in alphabetizedKeys
    process.stdout.write chalk.blue key
    if services[key].length > 0
      process.stdout.write " (#{ services[key].join(', ') })"
    process.stdout.write '\n'
  RSVP.resolve()

module.exports = (args, commandOptions, done) ->
  services = ServiceHelpers.listServicesWithEnvs commandOptions.config

  listServices services
    .then -> done?()
    .catch (e) ->
      console.error e?.stack or 'Aborting. '
      process.exit -1

