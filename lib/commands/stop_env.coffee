_ = require 'lodash'
ConsoleReporter = require '../lib/console_reporter'
Docker = require 'dockerode'
RSVP = require 'rsvp'
help = require './help'

stopContainer = (name, container, reporter) ->
  new RSVP.Promise (resolve, reject) ->
    reporter.startService(name).startTask('Stopping')

    container.stop (err, data) ->
      if err and err.statusCode isnt 304
        reporter.error err.json or "Error #{err.statusCode} stopping container"
      else
        reporter.succeedTask().finish()

      resolve()

module.exports = (args, options, done) ->
  docker = new Docker()

  if args.length isnt 1
    return help args, options, done

  env = args[0]

  reporter = options.reporter or new ConsoleReporter(process.stderr)

  docker.listContainers (err, containerInfos) ->
    throw err if err

    promise = RSVP.resolve()
    found = false

    for containerInfo in containerInfos
      id = containerInfo.Id

      for name in containerInfo.Names
        if name.match new RegExp("\.#{env}$")
          found = true

          do (id, name) ->
            promise = promise.then ->
              stopContainer name, docker.getContainer(id), reporter
          break

    if found
      promise.then done
    else
      reporter.message 'No containers found to stop'
      done?()
