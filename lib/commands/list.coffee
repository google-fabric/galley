_ = require 'lodash'
chalk = require 'chalk'
RSVP = require 'rsvp'

help = require './help'

ServiceHelpers = require '../lib/service_helpers'

displayServicesAndEnvs = (services) ->
  alphabetizedKeys = _.keys(services)
  alphabetizedKeys.sort()

  for key in alphabetizedKeys
    process.stdout.write chalk.blue key
    if services[key].length > 0
      process.stdout.write " (#{ services[key].join(', ') })"
    process.stdout.write '\n'

listServices = (services, addons) ->
  process.stdout.write 'Available Addons:\n'
  displayServicesAndEnvs(addons)

  process.stdout.write 'Available Services:\n'
  displayServicesAndEnvs(services)

  RSVP.resolve()

module.exports = (args, commandOptions, done) ->
  services = ServiceHelpers.listServicesWithEnvs commandOptions.config
  addons = ServiceHelpers.listAddons commandOptions.config

  listServices services, addons
    .then -> done?()
    .catch (e) ->
      console.error e?.stack or 'Aborting. '
      process.exit -1

