_ = require 'lodash'
chalk = require 'chalk'
Docker = require 'dockerode'
RSVP = require 'rsvp'
util = require 'util'
path = require 'path'
minimist = require 'minimist'
spin = require 'term-spinner'

help = require './help'

ConsoleReporter = require '../lib/console_reporter'
DockerArgs = require '../lib/docker_args'
DockerConfig = require '../lib/docker_config'
DockerUtils = require '../lib/docker_utils'
OverlayOutputStream = require '../lib/overlay_output_stream'
Rsyncer = require '../lib/rsyncer'
ServiceHelpers = require '../lib/service_helpers'

RECREATE_OPTIONS = ['all', 'stale', 'missing-link']

# Returns the configuration to pass in to createContainer based on the options (argv) and service
# configuration.
makeCreateOpts = (imageInfo, serviceConfig, servicesMap, options) ->
  containerNameMap = _.mapValues(servicesMap, 'containerName')

  createOpts =
    'name': serviceConfig.containerName
    'Image': imageInfo.Id
    'Env': DockerArgs.formatEnvVariables(serviceConfig.env)
    'User': serviceConfig.user
    'Volumes': DockerArgs.formatVolumes(serviceConfig.volumes)
    'HostConfig':
      'Links': DockerArgs.formatLinks(serviceConfig.links, containerNameMap)
      # Binds actually require no formatting. We pre-process when parsing args to make sure that
      # the host path is absolute, but beyond that these are just an array of
      # "host_path:container_path"
      'Binds': serviceConfig.binds
      'VolumesFrom': DockerArgs.formatVolumesFrom(serviceConfig.volumesFrom, containerNameMap)

  if serviceConfig.publishPorts
    {portBindings, exposedPorts} = DockerArgs.formatPortBindings(serviceConfig.ports)
    createOpts['HostConfig']['PortBindings'] = portBindings
    unless exposedPorts is {}
      createOpts['ExposedPorts'] = exposedPorts
      createOpts['HostConfig']['PublishAllPorts'] = true

  if serviceConfig.command?
    createOpts['Cmd'] = serviceConfig.command

  if serviceConfig.entrypoint?
    # We special case no entrypoint ("--entrypoint=") to an empty array to get
    # Docker to use its default non-entrypoint. (null / false stuff will get the
    # image's default)
    createOpts['Entrypoint'] = if serviceConfig.entrypoint is '' then [] else serviceConfig.entrypoint

  if serviceConfig.workdir?
    # We allow relative workdirs, which become relative to either / or the image's default workdir,
    # if it's set.
    defaultWorkingDir = imageInfo.Config.WorkingDir or '/'
    createOpts['WorkingDir'] = path.resolve(defaultWorkingDir, serviceConfig.workdir)

  if serviceConfig.attach
    _.merge createOpts,
      'Tty': options.stdin?.isTTY
      'OpenStdin': true
      # Causes Docker to close the input stream, which will automatically close STDIN due to the pipe
      'StdinOnce': true

  createOpts

# Downloads an image by name, showing progress on stderr.
#
# Returns a promise that resolves when the download is complete.
downloadServiceImage = (docker, imageName, options) ->
  options.reporter.startTask 'Downloading'

  progressLine = options.reporter.startProgress()

  DockerUtils.downloadImage docker, imageName, DockerConfig.authConfig, progressLine.set.bind(progressLine)
  .finally -> progressLine.clear()
  .then -> options.reporter.succeedTask()

# Inspects an image by name, downloading it if necessary.
#
# Returns a promise that resolves to a hash of the format:
#  image: the image, guaranteed to be locally downloaded
#  info: result of Dockerode's inspect
ensureImageAvailable = (docker, imageName, options) ->
  image = docker.getImage(imageName)

  DockerUtils.inspectImage image
  .catch (err) ->
    # A 404 is a legitimate error that an image of that name doesn't exist. So, try to pull it.
    throw err unless err?.statusCode is 404

    downloadServiceImage docker, imageName, options
    .then ->
      DockerUtils.inspectImage image

  .then ({image, info}) ->
    {image, info}

# Looks for an existing container for the service. If the options are to use a container with
# no set name, pretends it couldn't find anything.
#
# Returns a promise that resolves to a hash of the format:
#  container: the container, or null if none was found
#  info: result of inspecting the container, or null if it wasn't found
maybeInspectContainer = (docker, name) ->
  unless name
    RSVP.resolve {container: null, info: null}
  else
    DockerUtils.inspectContainer docker.getContainer(name)
    .then ({container, info}) -> {container, info}
    .catch (err) ->
      if err?.statusCode is 404 then {container: null, info: null}
      else throw err

# Helper method to check and see if the running container is missing links that we would
# configure for a fresh container. We do it just by count, rather than value. Important
# because deleting a container will remove its link from any container that is linking
# to it, requiring a complete re-create to connect.
isLinkMissing = (containerInfo, createOpts) ->
  runningLinkCount = containerInfo?.HostConfig?.Links?.length or 0
  createOpts.HostConfig.Links.length isnt runningLinkCount

isContainerImageStale = (containerInfo, imageInfo) ->
  imageInfo.Id isnt containerInfo.Config.Image

# Logic for whether we should remove / recreate a given container rather than just
# restart or keep it if it exits.
containerNeedsRecreate = (containerInfo, imageInfo, serviceConfig, createOpts, options, servicesMap) ->
  # Normally we make sure to start the "primary" service fresh, deleting it if it exists to get a
  # clean slate, but we don't do so in case of upReload and instead rely on the staleness / restart
  # checks to determine whether it needs a recreation.
  if serviceConfig.forceRecreate then true
  else if serviceConfig.stateful and not options.unprotectStateful then false
  else if isLinkMissing(containerInfo, createOpts) then true
  else if volumesFromFreshlyCreated(serviceConfig, servicesMap) then true
  else switch options.recreate
    when 'all' then true
    when 'stale' then isContainerImageStale(containerInfo, imageInfo)
    else false

# If the given container exists, but options are provided, removes the given container. We want to
# clear existing containers so that we can start fresh ones with the correct options configuration.
#
# Returns a promise that resolves to a hash of the format:
#  container: the container if it exists and wasn't removed, null if it didn't exist or was removed
maybeRemoveContainer = (container, containerInfo, imageInfo, serviceConfig, createOpts, options, servicesMap) ->
  new RSVP.Promise (resolve, reject) ->
    unless container?
      options.reporter.completeTask 'not found.'
      resolve {container: null}
    else if containerNeedsRecreate(containerInfo, imageInfo, serviceConfig, createOpts, options, servicesMap)
      options.reporter.completeTask('needs recreate').startTask('Removing')

      # When we want to get rid of a container, we want it gone. Use force to take it out if running.
      # Also, since this is for dev / testing purposes, delete associated volumes as well to keep
      # them from filling up the disk.
      promise = DockerUtils.removeContainer container, { force: true, v: true }
      .then ->
        options.reporter.succeedTask()
        {container: null}
      resolve promise
    else
      options.reporter.succeedTask 'ok'
      resolve {container}

# Makes sure that a container exists for the given service. May delete and recreate a container
# based on the logic of mayRemoveContainer.
#
# Returns a promise that resolves to a hash of the format:
#  container: the container, which has been created
#  info: result of Dockerode's inspect
ensureContainerConfigured = (docker, imageInfo, service, serviceConfig, options, servicesMap) ->
  options.reporter.startTask 'Checking'

  createOpts = makeCreateOpts imageInfo, serviceConfig, servicesMap, options

  maybeInspectContainer docker, serviceConfig.containerName
  .then ({container, info: containerInfo}) ->
    maybeRemoveContainer container, containerInfo, imageInfo, serviceConfig, createOpts, options, servicesMap
    .then ({container}) -> {container, info: containerInfo}

  .then ({container, info}) ->
    # At this point, we either have an existing container that we're happy with, or no container
    # at all and we need to create it.
    if container?
      servicesMap[service].freshlyCreated = false
      return {container, info}

    options.reporter.startTask 'Creating'
    DockerUtils.createContainer docker, createOpts
    .then ({container}) ->
      servicesMap[service].freshlyCreated = true
      DockerUtils.inspectContainer container

    .then ({container, info}) ->
      options.reporter.succeedTask()
      {container, info}

# Returns true if any of the services that serviceConfig depends on for a link have been
# "freshlyStarted," which is a signal that this service needs to be restarted to pick up IP or other
# changes. Does not take into account volumesFrom prereqs, as we don't need to restart if they
# are just restarted.
linkFreshlyStarted = (serviceConfig, completedServicesMap) ->
  for link in serviceConfig.links
    prereqService = link.split(':')[0]
    if completedServicesMap[prereqService]?.freshlyStarted
      return true
  return false

# Returns true if any of the services that serviceConfig depends on for volumesFrom have been
# created (e.g. due to being stale). Important so that we can recreate volumes to get new config
# data.
#
# CAVEAT(phopkins): This does not take into account source rsync mapping, though that typically
# would not affect us since the primary service container is always restarted. Might get wonky
# if you delete the source container and then SIGHUP, however.
volumesFromFreshlyCreated = (serviceConfig, completedServicesMap) ->
  for name in serviceConfig.volumesFrom
    prereqService = name.split(':')[0]
    if completedServicesMap[prereqService]?.freshlyCreated
      return true
  return false

# Makes sure that the container described by info is started. If the container has link
# prerequisites that were "freshly started" according to completedServicesMap, restarts to
# pick up any changes in IPs.
#
# Mutates completedServicesMap to add a record for this service with the format:
#  containerName: name of the service's container
#  freshlyStarted: true if this method started or restarted the service
#
# Returns a promise that resolves to a hash of the format:
#   container: the passed-through container, now started
ensureContainerStarted = (container, info, service, serviceConfig, options, completedServicesMap) ->
  # This will resolve to a boolean for whether or not the service was started / restarted or not.
  promise = null

  unless info.State.Running
    options.reporter.startTask 'Starting'
    promise = DockerUtils.startContainer(container).then -> true

  else if linkFreshlyStarted(serviceConfig, completedServicesMap)
    # If one of our prereqs was started, we probably have a stale IP for it, so have Docker
    # restart us.
    options.reporter.startTask 'Restarting'
    promise = DockerUtils.restartContainer(container).then -> true

  else
    promise = RSVP.resolve false

  promise
  .then (freshlyStarted) ->
    if freshlyStarted
      options.reporter.succeedTask()

    completedServicesMap[service].freshlyStarted = freshlyStarted

  .then -> {container}

# If options.attach is true, calls DockerUtils.attachContainer to get a stream. We do this before
# the container starts to make sure we get everything.
#
# Note that this only gets the container's output streams. We do input separately so that we can
# close input (e.g. from non-interactive sources like pipes) and still read the rest of the
# output.
#
# Resolves to a promise with a hash of the format:
#   container: passed through container
#   stream: attachment stream for the container, or null if the container shouldn't be attached
maybeAttachStream = (container, serviceConfig) ->
  new RSVP.Promise (resolve, reject) ->
    if serviceConfig?.attach
      promise = DockerUtils.attachContainer container,
        stream: true
        stdin: false
        stdout: true
        stderr: true
      .then ({container, stream}) -> {container, stream}
      resolve promise
    else
      resolve {container, stream: null}

# Pipes options.stdin into the container, setting up TTY mode if necessary.
#
# Detects if the connection is interrupted with CTRL-P CTRL-Q and, if so, destroys the outputStream
# so that the "maybePipeStdStreams" promise resolves (which happens when the stream ends).
attachInputStream = (container, outputStream, options) ->
  options.stdin.setEncoding 'utf8'

  DockerUtils.attachContainer container,
    stream: true
    stdin: true
    stdout: false
    stderr: false
  .then ({container, stream: inputStream}) ->
    # We save off this input stream on the sighupHandler so that it can close us when the SIGHUP
    # is caught.
    sighupHandler.inputStream = inputStream

    # Raw mode sends keystrokes and such over into the container for interactive shell use. We
    # need to unset when the stream closes to prevent certain host shells from not echoing input.
    if options.stdin.isTTY
      inputStream.setEncoding 'utf8'
      options.stdin.setRawMode true

    options.stdin.pipe inputStream, end: false

    # Boolean to keep track of whether STDIN has run out of data. If it has, and the socket closes,
    # we don't do anything. The container will process the input data, write data to the output
    # stream, and probably close naturally.
    #
    # If the socket closes and we haven't explicitly closed STDIN, that means that the container
    # was probably detached with CTRL-P CTRL-Q. In that case we forceably destroy the outputStream
    # in order to close it and resolve its promise. The container will still be running, so we'll
    # print out the "container detached" info below.
    inputEnded = false

    # If STDIN closes, we proxy that close through to the stream. This happens when e.g. data
    # piped on the command line runs out. Closing the stream essentially sends that EOF in to the
    # container.
    options.stdin.on 'end', ->
      inputEnded = true
      inputStream.end()

    # Handler to catch our connection closing to the Docker container for any reason, including:
    #  - stdin ending and us calling inputStream.end() above
    #  - container detaching due to CTRL-P CTRL-Q
    #  - stream being destroyed by the sighupHandler to kick us out of the attachment
    #
    # We dig into Dockerode's internal data to get the socket because it's the only reliable way
    # to detect the close. (Dockerode doesn't proxy the close that happens on CTRL-P CTRL-Q to
    # the stream, for example.)
    inputStream._output.socket.on 'close', ->
      options.stdin.setRawMode? false
      outputStream.destroy() unless inputEnded

# Pipes the provided container and its stream to stdout/stderr. If "stream" is null, just
# resolves immediately.
#
# Does a second attachment to stdin, which is kept separate so that stdin can close and still
# allow stdout info to flow.
#
# Returns a promise that resolves when the stream "ends," a sign that either the process has
# completed within the container, or the user has detached using CTRL-P CTRL-Q. The promise has a
# hash of the format:
#  container: the passed-through container
#  resolution: 'detached' if we didn't want to bind anyway, 'attached' if we bound and the stream
#    either completed (or was interrupted by CTRL-P CTRL-Q), 'sighup' if we stopped because of SIGHUP.
maybePipeStdStreams = (container, outputStream, options) ->
  return RSVP.resolve({container, resolution: 'detached'}) if outputStream is null

  attachInputStream container, outputStream, options
  .then ->
    new RSVP.Promise (resolve, reject) ->
      # The output stream will be closed naturally by Docker if the container stops, but we also
      # close it forceably above if the input stream becomes mysteriously detached.
      outputStream.on 'end', ->
        resolution = if sighupHandler.fired then 'sighup' else 'attached'
        resolve {container, resolution}

      if options.stdout.isTTY
        outputStream.setEncoding 'utf8'

        # For TTY we have a blended output of both STDOUT and STDERR
        outputStream.pipe options.stdout, end: true

        # Tells the container how big we are so that shell output looks nice, and keeps that
        # information up-to-date if you resize the host terminal window. We ignore the promises that
        # resizeContainer returns since it's ok to be async and/or fail.
        DockerUtils.resizeContainer container, options.stdout
        options.stdout.on 'resize', ->
          DockerUtils.resizeContainer container, options.stdout

      else
        outputStream.on 'end', ->
          try options.stdout.end() catch # ignore
          try options.stderr.end() catch # ignore

        # For non-TTY, we keep stdout and stderr separate, and pipe them appropriately to our
        # process's streams.
        container.modem.demuxStream outputStream, options.stdout, options.stderr

# Starts a given service, including downloading, creating, removing, and restarting and whatever
# else is necessary to get it going. Meant to be called in a loop with prerequisite services
# already started.
#
# If "options.primary" is false (or null) starts the service in the background with default options
# for its environment.
#
# Mutates the completedServicesMap to reflect any new state changes.
#
# Returns a promise that resolves to a hash of the format:
#  container: The container that was created
#  resolution: see maybePipeStdStreams
#
# If the container was attached, the promise resolves when the container's process completes, or
# when the stream is explicitly detached by the user. If the container was not attached, the
# promise resolves once the container has started.
startService = (docker, serviceConfig, service, options, completedServicesMap) ->
  # We write out our name as a prefix to both status messages and error messages
  options.reporter.startService service

  # This should never happen, since services in the prereq list should be unique
  if completedServicesMap[service]
    throw "Service already completed: #{service}"

  completedServicesMap[service] =
    containerName: null
    freshlyCreated: null
    freshlyStarted: null

  ensureImageAvailable docker, serviceConfig.image, options
  .then ({image, info: imageInfo}) ->
    ensureContainerConfigured docker, imageInfo, service, serviceConfig, options, completedServicesMap

  .then ({container, info: containerInfo}) ->
    completedServicesMap[service].containerName = containerInfo.Name

    maybeAttachStream container, serviceConfig
    .then ({container, stream}) -> {container, stream, info: containerInfo}

  .then ({container, stream, info: containerInfo}) ->
    ensureContainerStarted container, containerInfo, service, serviceConfig, options, completedServicesMap
    .then ({container}) ->
      options.reporter.finish() unless options.leaveReporterOpen
      maybePipeStdStreams container, stream, options
    .then ({container, resolution}) -> {container, resolution}

# We chown anything under the "source" directory to the original owner of the "source"
# directory, since if a Docker command created any files they'll be owned by root, which
# can cause problems when the directory is mapped out to the host.
#
# Returns a promise that resolves to true if we repaired source ownership, false otherwise.
maybeRepairSourceOwnership = (docker, config, service, options) ->
  serviceConfig = config[service] or {}
  unless options.repairSourceOwnership and serviceConfig.source?
    return RSVP.resolve(false)

  # This one-liner gets the user / group information via stat from the current directory ("."),
  # which we've set with WorkingDir to the service's source directory. It then recursively chowns
  # every file in that directory to that user / group.
  repairScript = "chown -R $(stat --format '%u:%g' .) ."

  createOpts =
    'Image': serviceConfig.image
    'Entrypoint': []
    'WorkingDir': serviceConfig.source
    'Cmd': [ 'bash', '-c', repairScript ]
    # We don't set ports or links or anything, as that's not relevant, but we do need the directory
    # bindings to affect files on the host machine.
    'HostConfig':
      'Binds': formatDirectoryBindings(options, serviceConfig)

  options.reporter.startTask 'Repairing source ownership'

  DockerUtils.createContainer(docker, createOpts)
  .then ({container}) ->
    DockerUtils.startContainer container
  .then ({container}) ->
    DockerUtils.waitContainer container
  .then ({container, result}) ->
    # Clear out volumes to try and keep them from accumulating
    DockerUtils.removeContainer container, { v: true }
    .then ->
      if result.StatusCode is 0
        options.reporter.succeedTask().finish()
      else
        options.reporter.error("Failed with exit code #{result.StatusCode}")
  .then -> true

# Called after an attachment to a container has stopped. Either the container has completed its
# process, in which case we determine the process's status code and remove the container, or the
# container is still running in which case we print out help about reattaching / removing.
#
# Resolves to a hash of the format:
#   container: the container
#   statusCode: if not null, the status code of the completed process
finalizeService = (container, options) ->
  DockerUtils.inspectContainer container
  .then ({container, info}) ->
    if info.State.Running
      # If the container is still running, then we got here by having our stream detached. So,
      # print out some help to let people know how to proceed from here.

      # Docker reports names canonically as beginning with a '/', which looks lame. Remove it.
      name = info.Name.replace /^\//, ''

      options.reporter.message ''
      options.reporter.message ''
      options.reporter.message chalk.gray('Container detached: ') + chalk.bold(name)
      options.reporter.message chalk.gray('Reattach with: ') + "docker attach #{name}"
      options.reporter.message chalk.gray('Remove with: ') + "docker rm -f #{name}"

      # If the stream was just detached, Docker doesn't end up closing it, so let's do that now.
      # Otherwise Node will keep the whole program open.
      options.stdin.end?()

      {container, statusCode: null}
    else
      statusCode = info.State.ExitCode
      if statusCode? and statusCode isnt 0
        options.reporter.error "#{info.Config.Cmd.join ' '} failed with exit code #{statusCode}"

      # Since the process exited, we remove the container. (Equivalent of --rm in Docker.)
      DockerUtils.removeContainer container
      .then -> {container, statusCode}

# Returns a callback suitable for sending to Rsyncer's "watch" method. Keeps a general status of
# "watching" or "syncing" with the directory being watched. When a sync is complete, flashes
# a "synched" message with the amount of time that the sync took.
#
# Writes the status message using options.stdout, which is assumed to be an OverlayOutputStream,
# and reports error messages using the standard reporter.
makeRsyncerWatchCallback = (options) ->
  lastTime = null
  spinner = spin.new()

  (status, source, files, error) ->
    switch status
      when 'watching'
        options.stdout.setOverlayStatus? "Watching #{path.basename source}…"
      when 'changed'
        lastTime = Date.now() if lastTime is null
      when 'syncing'
        spinner.next()
        options.stdout.setOverlayStatus? "#{spinner.current} Synching #{path.basename source}…"
      when 'synched'
        files = _.uniq files
        if files.length is 1
          desc = path.basename(files[0])
        else
          desc = "#{files.length} files"

        options.stdout.flashOverlayMessage? "Synched #{desc} (#{Date.now() - lastTime}ms)"
        lastTime = null
      when 'error'
        options.reporter.error error

# Wrapper before startup to set up mapping source into the service's container, if requested. If
# no --source flag is provided, no-ops.
#
# If --source is provided but not --rsync, modifies the service's config to add a "binds" entry to
# bring the --source value in to the container.
#
# If --rsync is also specified, starts up an rsync container to hold the source, performs a sync,
# and starts a watcher. Additionally modifies the service's config to bring the rsync container's
# volume in as a volumesFrom.
#
# If rsync is not needed, resolves to an empty hash. Otherwise, resolves to a hash with the format:
#  rsyncer: The Rsyncer object, useful for stopping later
prepareServiceSource = (docker, globalConfig, config, service, env, options) ->
  # We do a lot of short-circuiting returns up top to avoid the extra identation

  primaryServiceConfig = config[service]

  unless options.source
    return RSVP.reject '--rsync requires --source flag' if options.rsync
    return RSVP.resolve({})

  unless primaryServiceConfig.source
    return RSVP.reject '--rsync requires source configuration' 

  unless options.rsync
    primaryServiceConfig.binds.push "#{options.source}:#{primaryServiceConfig.source}"
    return RSVP.resolve({})

  rsyncConfig = globalConfig.rsync
  unless rsyncConfig?.image and rsyncConfig?.module
    return RSVP.reject '--rsync requires CONFIG.rsync image and module definitions'

  rsyncPort = rsyncConfig.port or 873
  suffix = rsyncConfig.suffix or 'rsync'

  rsyncServiceConfig = _.merge {}, ServiceHelpers.DEFAULT_SERVICE_CONFIG,
    containerName: "#{service}.#{suffix}"
    image: rsyncConfig.image
    ports: ["#{rsyncPort}"]
    publishPorts: true
    volumes: [primaryServiceConfig.source]

  # We tell startService to not "finish" the reporter's service so that we can include a
  # "syncing" task on the same line.
  #
  # TODO(phopkins): Make this less awkward.
  options = _.merge {}, options, leaveReporterOpen: true

  startService docker, rsyncServiceConfig, "#{service} (rsync)", options, {}
  .then ({container}) ->
    DockerUtils.inspectContainer container
  .then ({container, info}) ->
    # Now that we have the container running, make sure that the primary service will pull in its
    # volume for source code.
    primaryServiceConfig.volumesFrom.push info.Name

    options.reporter.startTask 'Syncing'
    progressLine = options.reporter.startProgress()
    # We don't have any text to display here, we just want the little progress spinner to spin.
    activityCb = -> progressLine.set ''

    # We do this to find what port rsync has been mapped to on the container host. We let it be
    # random (no ":" in the ports: value above) to avoid collision with other rsync containers.
    rsyncPortInfo = info.NetworkSettings.Ports["#{rsyncPort}/tcp"]

    rsyncer = new Rsyncer
      src: options.source
      dest: primaryServiceConfig.source
      # In boot2docker cases, local rsync will need to connect to the VM, which is what the Docker
      # modem has been talking to. If docker is running locally, the modem probably doesn't have a
      # host value (it would use 'socketPath' instead) so assume that 'localhost' will work.
      host: docker.modem.host or 'localhost'
      port: rsyncPortInfo[0].HostPort
      module: rsyncConfig.module

    # We do an initial sync before starting any other services so that the container will have
    # its latest files for when it starts up.
    rsyncer.sync activityCb
    .finally -> progressLine.clear()
    .then ->
      options.reporter.succeedTask().finish()

      rsyncer.watch makeRsyncerWatchCallback(options)

      {rsyncer}

# Starts up a dependency chain of services. services array must be in order so that dependencies
# come earlier.
#
# Returns a promise that resolves to the completedServicesMap, with service names keyed to hashes
# of the format:
#   containerName: name of the started container
#   freshlyStarted: true if the container was started / restarted in this Galley run
startServices = (docker, config, services, options) ->
  completedServicesMap = {}

  loopPromise = RSVP.resolve()
  _.forEach services, (service) ->
    loopPromise = loopPromise.then ->
      startService docker, config[service], service, options, completedServicesMap

  loopPromise.then -> completedServicesMap

# Parses out our command line args to return an object of the format:
#
#   service: name of the service we're starting up
#   env: ".env" suffix to use when configuring and naming the service and its prereqs
#   options: global modifications to our behavior
#   serviceConfigOverrides: values to merge into the Galleyfile configuration for the service
parseArgs = (args) ->
  argv = minimist args,
    # stopEarly allows --opts after the service name to be passed along to the container in command
    stopEarly: true
    boolean: [
      'detach'
      'repairSourceOwnership'
      'unprotectStateful'
      'rsync'
    ]
    alias:
      'add': 'a'
      'detach': 'd'
      'env': 'e'
      'source': 's'
      'user': 'u'
      'volume': 'v'
      'workdir': 'w'

  [service, envArr...] = (argv._[0] or '').split '.'
  env = envArr.join '.'

  options =
    recreate: 'stale'

  _.merge options, _.pick argv, [
    'recreate'
    'repairSourceOwnership'
    'rsync'
    'unprotectStateful'
  ]

  options.add = ServiceHelpers.normalizeAddonArgs argv.add 
  options.source = path.resolve(argv.source) if argv.source

  if RECREATE_OPTIONS.indexOf(options.recreate) is -1
    throw "Unrecognized recreate option: '#{options.recreate}'"

  # Set up values to be merged in to the Galleyfile configuration for the primary service.
  serviceConfigOverrides =
    # Causes us to bind to stdin / stdout / stderr on starting up
    attach: true
    # Used to hold --volume values off the command line
    binds: []
    env: {}
    # We will always want this service to be started completely fresh, to avoid any stale state
    forceRecreate: true
    # Also default to mapping this service's ports to the host
    publishPorts: true

  # The first element of argv._ is the service name, so if there's anything past that it means that
  # the user is specifying a command. In that case, we pull in that command, make the container
  # anonymous (so that it doesn't collide with a default version of the service already running),
  # and also don't publish ports to avoid collision.
  if argv._.length > 1
    _.merge serviceConfigOverrides,
      command: argv._.slice(1)
      containerName: ''
      publishPorts: false

  _.merge serviceConfigOverrides, _.pick argv, [
    'entrypoint'
    'user'
    'workdir'
  ]

  # Type coercion to an array from either an array or a single value, or undefined.
  #
  # Adding to the "env" map will merge these values over any env that the service config has,
  # rather than replacing the "env" wholesale. This has the desired behavior of the command line
  # overriding the config values as well.
  for envVar in [].concat(argv.env or [])
    [name, val] = envVar.split '='
    serviceConfigOverrides.env[name] = val

  if argv.detach then serviceConfigOverrides.attach = false
  if argv.name? then serviceConfigOverrides.containerName = argv.name
  if argv.volume?
    volumes = ServiceHelpers.normalizeVolumeArgs(argv.volume)
    serviceConfigOverrides.binds = serviceConfigOverrides.binds.concat(volumes)

  {service, env, options, serviceConfigOverrides}

# Method to actually perform the command, broken out so we can call it recursively in the case
# of a HUP reload.
#
# Resolves to promise with the hash:
#   statusCode: the statusCode of the container's process if it ran to completion, 0 if we detached,
#     or -1 if there was an error.
go = (docker, servicesConfig, services, options) ->
  sighupHandler.fired = false
  sighupHandler.inputStream = null

  # TODO(phopkins): Don't assume that the last service is the primary one once we implement
  # triggers.
  service = services.pop()

  startServices docker, servicesConfig, services, options
  .then (completedServicesMap) ->
    # Pass through completedServicesMap so we can re-use any auto-generated name for the
    # service container when HUP-reloading below.
    startService docker, servicesConfig[service], service, options, completedServicesMap
    .then ({container, resolution}) -> {container, resolution, completedServicesMap}

  .then ({container, resolution, completedServicesMap}) ->
    switch resolution
      when 'detached' then {statusCode: 0}
      when 'sighup'
        options.reporter.message()
        options.reporter.message chalk.gray "#{chalk.bold 'SIGHUP' } received. Rechecking containers.\n"

        # If we're going around again, re-use the same container name, even if
        # auto-created. Strip off the leading '/' though or inspecting by name won't work.
        # We also disable the "forceRecreate" behavior so that if the container doesn't need
        # to be recreated due to volume / link changes it won't be.
        primaryServiceConfig = servicesConfig[service]
        primaryServiceConfig.containerName ||= completedServicesMap[service].containerName.replace /^\//, ''
        primaryServiceConfig.forceRecreate = false

        # We have to add "service" back on to the list of prereqs.
        #
        # TODO(phopkins): Clean this up a bit when triggers are in place and the
        # primary service is less special.
        go docker, servicesConfig, services.concat(service), options

      when 'attached'
        maybeRepairSourceOwnership docker, servicesConfig, service, options
        .then -> finalizeService container, options
        .then ({container, statusCode}) -> {statusCode}

      else throw "Unknown resolution: #{resolution}"

  .catch (err) ->
    if err? and err isnt '' and typeof err is 'string' or err.json?
      message = (err?.json or (err if typeof err is 'string') or err?.message or 'Unknown error').trim()
      message = message.replace /^Error: /, ''
      options.reporter.error chalk.bold('Error:') + ' ' + message

    options.reporter.finish()
    options.stderr.write err?.stack if err?.stack

    {statusCode: -1}

# Handler for SIGHUP, which will cause Galley to essentially restart. The difference is that
# it will not remove the primary container, and will not recreate it unless a prerequisite
# has changed. Useful for after a pull.
#
# We mark that a HUP happened and then terminate the input stream. When that socket closes,
# we close the output stream, which is the trigger to either resolve or reject the attachment
# promise (which is where execution is tied up during the container's run).
sighupHandler = ->
  if sighupHandler.inputStream
    # We mark ourselves as "fired" so that the attach promise rejects, jumping execution to
    # go's catch blocks.
    sighupHandler.fired = true
    sighupHandler.inputStream.destroy()

module.exports = (args, commandOptions, done) ->
  {service, env, options, serviceConfigOverrides} = parseArgs(args)

  unless service? and not _.isEmpty(service)
    return help args, commandOptions, done

  options.stdin = commandOptions.stdin or process.stdin
  options.stderr = commandOptions.stderr or process.stderr
  options.stdout = commandOptions.stdout or new OverlayOutputStream(process.stdout)

  options.reporter = commandOptions.reporter or new ConsoleReporter(options.stderr)

  {globalConfig, servicesConfig} = ServiceHelpers.processConfig(commandOptions.config, env, options.add)

  primaryServiceConfig = servicesConfig[service]
  _.merge primaryServiceConfig, serviceConfigOverrides

  # We want to generate this before prepareServiceSource so that its potential modifications
  # to "volumesFrom" don't appear as additional prereq services.
  services = ServiceHelpers.generatePrereqServices(service, servicesConfig)

  docker = new Docker(DockerConfig.connectionConfig())

  process.on 'SIGHUP', sighupHandler

  prepareServiceSource docker, globalConfig, servicesConfig, service, env, options
  .then ({rsyncer}) ->
    go docker, servicesConfig, services, options
    .finally ->
      rsyncer?.stop()
  .then ({statusCode}) ->
    process.removeListener 'SIGHUP', sighupHandler
    done statusCode
  .catch (err) ->
    console.error "UNCAUGHT EXCEPTION IN RUN COMMAND"
    console.error err
    console.error err?.stack if err?.stack
    process.exit 255

# Exposed for unit testing
module.exports.parseArgs = parseArgs

