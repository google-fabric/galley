_ = require 'lodash'
chalk = require 'chalk'
RSVP = require 'rsvp'

help = require './help'

ServiceHelpers = require '../lib/service_helpers'

listServices = (galleyfilePath, out, serviceEnvMap, serviceAddonMap) ->
  out.write "#{ chalk.bold 'Galleyfile:' } #{galleyfilePath}\n"

  alphabetizedKeys = _.keys(serviceEnvMap)
  alphabetizedKeys.sort()

  for key in alphabetizedKeys
    out.write '  ' + chalk.blue key
    envs = (".#{env}" for env in serviceEnvMap[key])
    if envs.length > 0
      out.write chalk.gray(" [#{ envs.join(', ') }]")

    addons = serviceAddonMap[key] or []
    if addons.length > 0
      out.write chalk.green(" -a #{ addons.join(' ')}")
    out.write '\n'

  RSVP.resolve()

module.exports = (args, commandOptions, done) ->
  serviceEnvMap = ServiceHelpers.envsByService commandOptions.config
  serviceAddonMap = ServiceHelpers.addonsByService commandOptions.config

  listServices commandOptions.configPath, (commandOptions.stdout or process.stdout), serviceEnvMap, serviceAddonMap
    .then -> done?()
    .catch (e) ->
      console.error e?.stack or 'Aborting. '
      process.exit -1
