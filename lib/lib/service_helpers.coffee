RSVP = require 'rsvp'
_ = require 'lodash'
path = require 'path'

DEFAULT_SERVICE_CONFIG =
  binds: []
  command: null
  entrypoint: null
  env: {}
  image: null
  links: []
  ports: []
  restart: false
  source: null
  stateful: false
  user: ''
  volumesFrom: []

ENV_COLLAPSED_ARRAY_CONFIG_KEYS = ['links', 'ports', 'volumesFrom']

# Accept a value for argv options and normalize it to handle multiple comma delimited values in strings
# while ensuring that the return value is always a flat array of Strings. Used by both -a and
# --volumes-from.
#
# e.g.:
#
# undefined -> []
# 'beta' -> ['beta']
# ['beta'] -> ['beta']
# 'beta,other' -> ['beta', 'other']
# ['beta', 'other'] -> ['beta', 'other']
# ['beta', 'other,third'] -> ['beta', 'other', 'third']
# 'beta,' -> ['beta']
# ',beta' -> ['beta']
normalizeMultiArgs = (addonOptions) ->
  toReturn = addonOptions

  # minimist will turn repeatable args (like --add) into an array, but in case there's just one,
  # or none, let's always present the value as an array for simplicity of consumption
  if _.isString(toReturn)
    toReturn = [toReturn]
  else if _.isUndefined(toReturn)
    toReturn = []

  # Now, for each entry in the array, handle comma delimited multiple values by flat-mapping a split
  # on commas, and rejecting empty strings
  _.flatten(_.map(toReturn, (val) ->
    if val.indexOf(",") > -1
      _.filter(val.split(","), (val) -> val.length > 0)
    else
      val
  ))

# Converts the "--volume" argv value into an array of volume mappings, resolving any host paths
# relative to the current working directory.
normalizeVolumeArgs = (volumeOptions) ->
  # Compensate for minimist giving a string value for single use and an array for multiple use
  volumes = if _.isArray(volumeOptions) then volumeOptions else [volumeOptions]

  _.map volumes, (volume) ->
    [host_path, container_path] = volume.split(':')
    "#{path.resolve(host_path)}:#{container_path}"


lookupEnvValue = (hash, env, defaultValue) ->
  defaultValue = [] if defaultValue is undefined

  [env, namespace] = env.split('.')
  val = hash["#{env}.#{namespace}"] || hash[env]

  # Use existance check rather than just falsey so that val can be ''
  if val? then val else defaultValue

lookupEnvArray = (value, env) ->
  value = value or []
  if _.isArray value
    value
  else
    lookupEnvValue value, env

# serviceConfig: a hash from the Galleyfile for a particular service
# env: string of the form "env" or "env.namespace"
#
# Returns serviceConfig flattened down to only the given env
collapseServiceConfigEnv = (serviceConfig, env) ->
  collapsedServiceConfig = _.mapValues serviceConfig, (value, key) ->
    if ENV_COLLAPSED_ARRAY_CONFIG_KEYS.indexOf(key) isnt -1
      collapseEnvironment value, env, []
    else if key is 'env'
      # value here is a hash of 'ENV_VAR_NAME': <string or hash>
      _.mapValues value, (envValue, envKey) ->
        collapseEnvironment envValue, env, null
    else
      value

  collapsedServiceConfig

# service: the service who's serviceConfig is being examined
# env: the requested env
# serviceConfig: the service config, collapsed by env for this service
# requestedAddons: the addons requested in the command
# globalAddons: the possible addons that can be requested
#
# Given a service, an env, and addons, this adds the requested addons to the serviceConfig
# including links, ports, volumes and env variables. Supports addons with environments.
combineAddons = (service, env, serviceConfig, requestedAddons, globalAddons) ->
  for addonName in requestedAddons
    addon = globalAddons[addonName]
    throw "Addon #{addonName} not found in ADDONS list in Galleyfile" unless addon?

    serviceAddon = addon[service]
    if serviceAddon?
      for key in ENV_COLLAPSED_ARRAY_CONFIG_KEYS
        if serviceAddon[key]?
          addonValue = collapseEnvironment serviceAddon[key], env, []
          serviceConfig[key] = serviceConfig[key].concat addonValue

        if serviceAddon.env?
          addonEnv = _.mapValues serviceAddon.env, (envValue, envKey) ->
            collapseEnvironment envValue, env, null
          serviceConfig.env = _.merge {}, serviceConfig.env, addonEnv
  serviceConfig

addDefaultNames = (globalConfig, service, env, serviceConfig) ->
  serviceConfig.name = service
  serviceConfig.containerName = "#{service}.#{env}"
  serviceConfig.image ||= _.compact([globalConfig.registry, service]).join '/'
  serviceConfig

# Takes a Galleyfile configuration, environment suffix, and list of addons from the command line,
# and returns a hash of the format:
#  servicesConfig: service name to serviceConfig map
#  globalConfig: global configuration data (e.g. rsync or registry info)
#
# The servicesConfig is processed and normalized in the following ways:
#   - Missing keys and values are added so that each service has a value for everything in
#     DEFAULT_SERVICES_CONFIG
#   - Image and container names are filled in
#   - Environments are "collapsed": e.g. the service's "links" values are those links specified for
#     the passed in "env" value.
#   - Addons are expanded and merged in to the other values.
#
# Callers of this method therefore need not worry about any further parameterization based on env
# or addons.
processConfig = (galleyfileValue, env, requestedAddons) ->
  globalConfig = galleyfileValue.CONFIG or {}
  globalAddons = galleyfileValue.ADDONS or {}

  servicesConfig = _.mapValues galleyfileValue, (serviceConfig, service) ->
    return if service is 'CONFIG'

    # TOOD(phopkins): Raise exception if unrecognized key in serviceConfig

    serviceConfig = _.merge {}, DEFAULT_SERVICE_CONFIG, serviceConfig

    serviceConfig = collapseServiceConfigEnv serviceConfig, env
    serviceConfig = combineAddons service, env, serviceConfig, requestedAddons, globalAddons
    serviceConfig = addDefaultNames globalConfig, service, env, serviceConfig
    serviceConfig

  # Remove the globalConfig from the servicesConfig to keep it from accidentally being used as a
  # service called "CONFIG".
  delete servicesConfig.CONFIG

  {globalConfig, servicesConfig}

collapseEnvironment = (configValue, env, defaultValue) ->
  if _.isObject(configValue) and not _.isArray(configValue)
    lookupEnvValue configValue, env, defaultValue
  else
    if configValue? then configValue else defaultValue

envsFromServiceConfig = (serviceConfig) ->
  definedEnvs = for parametrizeableKey, value of _.pick(serviceConfig, ['links', 'ports', 'volumesFrom'])
    if not value or _.isArray(value)
      []
    else
      _.keys(value)

  envEnvs = for variable, value of serviceConfig['env']
    if _.isArray(value) or _.isString(value)
      []
    else
      _.keys(value)

  definedEnvs = definedEnvs.concat(envEnvs)
  _.unique _.flatten definedEnvs

listServicesWithEnvs = (galleyfileValue) ->
  serviceList = _.mapValues galleyfileValue, (serviceConfig, service) ->
    return if service is 'CONFIG' or service is 'ADDONS'
    envsFromServiceConfig serviceConfig

  delete serviceList.CONFIG
  delete serviceList.ADDONS
  serviceList

listAddons = (galleyfileValue) ->
  addons = galleyfileValue['ADDONS'] or {}
  _.keys(addons)

# Generates an array of prerequisite services of a service, from the configuration file.
# The last element of returned array is the requested service,
# and strict ordering is maintained for the rest, such that no service comes before
# a service that it depends on.
generatePrereqServices = (service, servicesConfig) ->
  _.uniq generatePrereqsRecursively(service, servicesConfig).reverse()

# foundServices: contains the ordered list of services that have been discovered by the depth first recursion
# pendingServices: contains the immediate dependency chain in order to reject circular dependecies
# both are built up recursively
generatePrereqsRecursively = (service, servicesConfig, pendingServices = [], foundServices = []) ->
  nextFoundServices = foundServices.concat service
  serviceConfig = servicesConfig[service]

  throw "Missing config for service: #{service}" unless serviceConfig

  links = serviceConfig.links
  volumesFroms = serviceConfig.volumesFrom

  prereqs = links.concat volumesFroms

  _.forEach prereqs, (prereqName) ->
    prereqService = prereqName.split(':')[0]

    if (circularIndex = pendingServices.indexOf(prereqService)) isnt -1
      dependencyServices = foundServices.slice(circularIndex)
      dependencyServices.push service, prereqService
      # trigger error handling for the circular dependency
      throw "Circular dependency for #{prereqService}: #{dependencyServices.join ' -> '}"

    nextPendingServices = pendingServices.concat service
    nextFoundServices = generatePrereqsRecursively(prereqService, servicesConfig, nextPendingServices, nextFoundServices)
  nextFoundServices

module.exports = {
  DEFAULT_SERVICE_CONFIG
  normalizeMultiArgs
  normalizeVolumeArgs
  addDefaultNames
  generatePrereqServices
  collapseEnvironment
  combineAddons
  collapseServiceConfigEnv
  processConfig
  listServicesWithEnvs
  listAddons
}

