_ = require 'lodash'
chalk = require 'chalk'
minimist = require 'minimist'

ConsoleReporter = require '../lib/console_reporter'
Docker = require 'dockerode'
DockerConfig = require '../lib/docker_config'
DockerUtils = require '../lib/docker_utils'
PromiseUtils = require '../lib/promise_utils'
ServiceHelpers = require '../lib/service_helpers'
RSVP = require 'rsvp'
help = require './help'

# Docker lists out all the names a container is known by, which includes names from containers that
# link to it. We use the heuristic that if there's only one "/" in the name then it's the "real"
# name for the container. (The "/" is used to separate the container name and its link name.)
findContainerName = (info) ->
  for name in info.Names
    return name.substr(1) if (name.match(/\//g) or []).length is 1

# Given a service name and env, reverse-engineered from a container name, use the env to generate
# the flattened config so we can see how the service was configured. Important for determining if
# a service is "stateful" or not.
lookupServiceConfig = (service, env, options, configCache) ->
  unless configCache[env]?
    configCache[env] = ServiceHelpers.processConfig(options.config, env, []).servicesConfig

  configCache[env][service]

# Removes a stopped container if it either does not have a Galleyesq name (no ".") or if it is for
# a service that does not appear to be stateful.
maybeRemoveContainer = (docker, info, options, configCache) ->
  containerName = findContainerName(info)

  [service, envParts...] = containerName.split('.')
  env = envParts.join('.')

  if env.length and (config = lookupServiceConfig service, env, options, configCache)
    anonymousContainer = false
    statefulContainer = config.stateful
  else
    # If there's no env or if the service isn't in our config, treat it as anonymous (i.e. not
    # managed by Galley).
    anonymousContainer = true
    statefulContainer = false

  # Short-circuit out here without reporting anything.
  return RSVP.resolve() if anonymousContainer and not options.unprotectAnonymous

  options.reporter.startService containerName

  removePromise = unless statefulContainer and not options.unprotectStateful
    options.reporter.startTask 'Removing'

    DockerUtils.removeContainer docker.getContainer(info.Id), { v: true }
    .then ->
      options.reporter.succeedTask()
  else
    options.reporter.completeTask 'Preserving stateful service'
    RSVP.resolve({})

  removePromise
  .finally ->
    options.reporter.finish()

# Removes a dangling image, ignoring any "still in use" errors since those can come up naturally
# when an old container refers to an image whose original tag has moved on.
removeImage = (docker, info) ->
  DockerUtils.removeImage docker.getImage(info.Id)
  .catch (err) ->
    # Sometimes containers are using untagged images, for example a long-lived stateful container
    # after a newer image has been downloaded.
    if err.statusCode is 409 then return
    else throw err

module.exports = (args, commandOptions, done) ->
  argv = minimist args,
    boolean: [
      'help'
      'unprotectAnonymous'
      'unprotectStateful'
    ]

  if argv._.length isnt 0 or argv.help
    return help args, commandOptions, done

  docker = new Docker(DockerConfig.connectionConfig())

  options =
    unprotectStateful: argv.unprotectStateful
    unprotectAnonymous: argv.unprotectAnonymous
    stderr: commandOptions.stderr or process.stderr
    reporter: commandOptions.reporter or new ConsoleReporter(process.stderr)
    config: commandOptions.config

  # Cache used to store env -> serviceConfigs
  configCache = {}

  DockerUtils.listContainers docker, filters: '{"status": ["exited"]}'
  .then ({infos}) ->
    options.reporter.message 'Removing stopped containers…'
    PromiseUtils.promiseEach infos, (info) ->
      maybeRemoveContainer(docker, info, options, configCache)
  .then ->
    DockerUtils.listImages docker, filters: '{"dangling": ["true"]}'
  .then ({infos}) ->
    # Short-circuit out for acceptance tests. We can't effectively test this part because your
    # global state is arbitrary (and we don't want to affect it).
    return if commandOptions.preserveUntagged

    options.reporter.message()
    count = 0

    progressLine = options.reporter.startProgress 'Deleting dangling images…'
    updateProgress = -> progressLine.set "#{count} / #{infos.length}"
    updateProgress()

    PromiseUtils.promiseEach infos, (info) ->
      removeImage docker, info
      .then ->
        count++
        updateProgress()
    .then ->
      progressLine.clear()
      options.reporter.succeedTask()
      options.reporter.finish()
  .then ->
    done()
  .catch (err) ->
    if err? and err isnt '' and typeof err is 'string' or err.json?
      message = (err?.json or (err if typeof err is 'string') or err?.message or 'Unknown error').trim()
      message = message.replace /^Error: /, ''
      options.reporter.error chalk.bold('Error:') + ' ' + message

    options.reporter.finish()
    options.stderr.write err?.stack if err?.stack
