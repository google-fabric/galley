_ = require 'lodash'
chalk = require 'chalk'
Docker = require 'dockerode'
RSVP = require 'rsvp'
minimist = require 'minimist'

help = require './help'

ProgressLine = require '../lib/progress_line'
DockerConfig = require '../lib/docker_config'
DockerUtils = require '../lib/docker_utils'
ServiceHelpers = require '../lib/service_helpers'

parseArgs = (args) ->
  argv = minimist args,
    alias:
      'add': 'a'

  [service, envArr...] = (argv._[0] or '').split '.'
  env = envArr.join '.'

  options = {}

  _.merge options, _.pick argv, [
    'add'
  ]

  options.add = ServiceHelpers.normalizeMultiArgs options.add

  {service, env, options}

pullService = (docker, servicesConfig, service, env) ->
  prereqsArray = ServiceHelpers.generatePrereqServices(service, servicesConfig)

  prereqPromise = RSVP.resolve()
  _.forEach prereqsArray, (prereq) ->
    imageName = servicesConfig[prereq].image
    progressLine = new ProgressLine process.stderr, chalk.gray

    prereqPromise = prereqPromise
    .then ->
      process.stderr.write chalk.blue(prereq + ':')
      process.stderr.write chalk.gray(' Pulling… ')

      DockerUtils.downloadImage(docker, imageName, DockerConfig.authConfig, progressLine.set.bind(progressLine))
    .finally ->
      progressLine.clear()
    .then ->
      process.stderr.write chalk.green(' done!')
    .catch (err) ->
      if err?.statusCode is 404
        throw "Image #{imageName} not found in registry"
      else
        throw err
    .catch (err) ->
      if err? and err isnt '' and typeof err is 'string' or err.json?
        process.stderr.write chalk.red(' ' + chalk.bold('Error:') + ' ' + (err?.json or err).trim())
        throw ''
      else
        throw err
    .finally ->
      process.stderr.write '\n'

  prereqPromise

module.exports = (args, commandOptions, done) ->
  {service, env, options} = parseArgs(args)

  unless service? and not _.isEmpty(service)
    return help args, commandOptions, done

  {servicesConfig} = ServiceHelpers.processConfig commandOptions.config, env, options.add
  docker = new Docker(DockerConfig.connectionConfig())

  pullService docker, servicesConfig, service, env
    .then -> done?()
    .catch (e) ->
      console.error e?.stack or 'Aborting. '
      process.exit -1

