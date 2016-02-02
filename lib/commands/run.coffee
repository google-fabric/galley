_ = require 'lodash'
chalk = require 'chalk'
Docker = require 'dockerode'
RSVP = require 'rsvp'
util = require 'util'
path = require 'path'
minimist = require 'minimist'
spin = require 'term-spinner'
running = require 'is-running'

help = require './help'

ConsoleReporter = require '../lib/console_reporter'
DockerArgs = require '../lib/docker_args'
DockerConfig = require '../lib/docker_config'
DockerUtils = require '../lib/docker_utils'
LocalhostForwarder = require '../lib/localhost_forwarder'
OverlayOutputStream = require '../lib/overlay_output_stream'
Rsyncer = require '../lib/rsyncer'
ServiceHelpers = require '../lib/service_helpers'
StdinCommandInterceptor = require '../lib/stdin_command_interceptor'

RECREATE_OPTIONS = ['all', 'stale', 'missing-link']

# Returns the configuration to pass in to createContainer based on the options (argv) and service
# configuration.
makeCreateOpts = (imageInfo, serviceConfig, servicesMap, options) ->
  containerNameMap = _.mapValues(servicesMap, 'containerName')

  volumesFrom = DockerArgs.formatVolumesFrom(serviceConfig.volumesFrom, containerNameMap)
    .concat(serviceConfig.containerVolumesFrom or [])

  createOpts =
    'name': serviceConfig.containerName
    'Image': imageInfo.Id
    'Env': DockerArgs.formatEnvVariables(serviceConfig.env)
    'Labels':
      'io.fabric.galley.primary': 'false'
    'User': serviceConfig.user
    'Volumes': DockerArgs.formatVolumes(serviceConfig.volumes)
    'HostConfig':
      'ExtraHosts': ["#{serviceConfig.name}:127.0.0.1"]
      'Links': DockerArgs.formatLinks(serviceConfig.links, containerNameMap)
      # Binds actually require no formatting. We pre-process when parsing args to make sure that
      # the host path is absolute, but beyond that these are just an array of
      # "host_path:container_path"
      'Binds': serviceConfig.binds
      'VolumesFrom': volumesFrom

  if serviceConfig.publishPorts
    {portBindings, exposedPorts} = DockerArgs.formatPortBindings(serviceConfig.ports)
    createOpts['HostConfig']['PortBindings'] = portBindings
    createOpts['ExposedPorts'] = exposedPorts

  # Note container labels and values (as of Docker 1.6) can only be strings
  if serviceConfig.primary?
    createOpts['Labels']['io.fabric.galley.primary'] = 'true'
    createOpts['Labels']['io.fabric.galley.pid'] = "#{process.pid}"

  if serviceConfig.command?
    createOpts['Cmd'] = serviceConfig.command

  if serviceConfig.restart
    createOpts['HostConfig']['RestartPolicy'] = { 'Name': 'always' }

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

# Helper method to check and see if the running container's links differ from the ones we would
# want to create it with. If they do differ, the only recourse is to remove and recreate the
# container, since you may not (currently) modify links of a running container.
isLinkMissing = (containerInfo, createOpts) ->
  # These are the links as reported back by Docker, which have the format:
  #  /sourceContainer:/destContainer/alias
  # We do a bit of splitting and joining to convert them back to /sourceContainer:alias so that
  # we can compare them directly with the Links parameter we provide to create.
  currentLinks = _.map (containerInfo?.HostConfig?.Links or []), (link) ->
    [source, dest] = link.split(':')
    "#{source}:#{dest.split('/').pop()}"

  # Make a copy since sort mutates.
  requestedLinks = createOpts.HostConfig.Links.concat()

  currentLinks.sort()
  requestedLinks.sort()

  not _.isEqual(currentLinks, requestedLinks)

# Docker API 1.20 switched from a "Volumes" map of container paths to filesystem paths to a "Mounts"
# array of mount information. This function adapts to give the "Volumes" format in all cases.
extractVolumesMap = (containerInfo) ->
  if containerInfo.Mounts?
    _.tap {}, (volumesMap) ->
      for mount in containerInfo.Mounts
        volumesMap[mount.Destination] = mount.Source
  else
    containerInfo.Volumes or {}

# Compares the paths we expect volumes to have, based on the completedServicesMap, with the paths
# for those volumes from the containerInfo. If there is a discrepency, the container will need to
# be recreated in order to get the latest volumes.
areVolumesOutOfDate = (containerInfo, serviceConfig, completedServicesMap) ->
  # This becomes an array of objects that map mount points within the container to directories on
  # the Docker host machine, for each service that our service takes its volumesFrom.
  volumePathsArray = _.map (serviceConfig.volumesFrom or []), (service) ->
    completedServicesMap[service].volumePaths

  # Given the above, we can then merge down into an empty object to get a single map of mount
  # points to paths. We expect that this order is correct if services have colliding VOLUME
  # declarations, but YMMV. Best not to get in that situation.
  expectedVolumes = _.merge.apply _, [{}].concat volumePathsArray

  # We only validate the paths from expectedVolumes, rather than doing a full deep equality check,
  # since the container's *own* VOLUMEs will appear in its Volumes map, along with the ones from
  # VolumesFrom (which are the only ones we validate).
  containerVolumes = extractVolumesMap containerInfo
  for mountPoint, volumePath of expectedVolumes
    return true if containerVolumes[mountPoint] isnt volumePath

  return false

# Returns true if the container's image doesn't match the one from imageInfo, which we looked up
# from the image the service is configured to run with.
isContainerImageStale = (containerInfo, imageInfo) ->
  imageInfo.Id isnt containerInfo.Config.Image

# Logic for whether we should remove / recreate a given container rather than just
# restart or keep it if it exits.
containerNeedsRecreate = (containerInfo, imageInfo, serviceConfig, createOpts, options, servicesMap) ->
  # Normally we make sure to start the "primary" service fresh, deleting it if it exists to get a
  # clean slate, but we don't do so in case of upReload and instead rely on the staleness / restart
  # checks to determine whether it needs a recreation.
  if serviceConfig.stateful and not options.unprotectStateful then false
  else if serviceConfig.forceRecreate then true
  else if isLinkMissing(containerInfo, createOpts) then true
  else if areVolumesOutOfDate(containerInfo, serviceConfig, servicesMap) then true
  else switch options.recreate
    when 'all' then true
    when 'stale' then isContainerImageStale(containerInfo, imageInfo)
    else false

# Checks the container metadata contained in labels to determine if the container was started by
# another galley process as the primary container.
containerIsCurrentlyGalleyManaged = (containerInfo) ->
  if containerInfo.Config.Labels? and containerInfo.Config.Labels['io.fabric.galley.primary'] is 'true'
    pid = parseInt(containerInfo.Config.Labels['io.fabric.galley.pid'])
    if pid is not process.pid
      running pid

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
      # check to see if the container that needs to be recreated is already managed by
      # galley (somewhere else). If it is, we can't recreate it, since it will bust that galley
      # session. Instead, just error out.
      if containerIsCurrentlyGalleyManaged(containerInfo)
        reject "Cannot be recreated, container is managed by another Galley process.\n
          Check that all images are up to date, and that addons requested here match
          those in the managed Galley container."
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

# Makes sure that the container described by info is started, starting it up and unpausing it if
# necessary.
#
# Returns a promise that resolves to a hash of the format:
#   container: the passed-through container, now started
#   info: an up-to-date inspection of the container
ensureContainerRunning = (container, info, service, serviceConfig, options) ->
  actionPromise = null

  unless info.State.Running
    options.reporter.startTask 'Starting'
    actionPromise = DockerUtils.startContainer(container)
  else if info.State.Paused
    options.reporter.startTask 'Unpausing'
    actionPromise = DockerUtils.unpauseContainer(container)
  else
    # Nothing to do, so short-circuit.
    return RSVP.resolve {container, info}

  actionPromise
  .then ->
    DockerUtils.inspectContainer(container)
  .then ({container, info}) ->
    options.reporter.succeedTask()
    if serviceConfig.containerName is ''
      options.reporter.completeTask "#{chalk.gray 'Running as:'} #{chalk.bold info.Name.substring(1)}"
    {container, info}

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

# Pipes the provided container and its stream to stdout/stderr. If "stream" is null, just
# resolves immediately.
#
# Does a second attachment to stdin, which is kept separate so that stdin can close and still
# allow stdout info to flow.
#
# Returns a promise that resolves when the stream "ends," a sign that either the process has
# completed within the container, the user has detached or issued another CTRL-P command, or the
# process is being restarted by the RestartPolicy. The promise has a hash of the format:
#  container: the passed-through container
#  resolution: one of the following values:
#    "end": output stream has closed, either because the command completed or it's restarting
#    "detach": the user has triggered a detachment from the running container
#    "stop": the user has requested we stop the container
#    "reload": the user has requested Galley re-run, re-checking dependencies and recreating the
#       primary container if necessary
#    "unattached": we weren't asked to attach in the first place
maybePipeStdStreams = (container, outputStream, options) ->
  return RSVP.resolve({container, resolution: 'unattached'}) if outputStream is null

  DockerUtils.attachContainer container,
    stream: true
    stdin: true
    stdout: false
    stderr: false
  .then ({container, stream: inputStream}) ->
    options.stdinCommandInterceptor.start(inputStream)

    # Tells the container how big we are so that shell output looks nice, and keeps that
    # information up-to-date if you resize the host terminal window. We ignore the promises that
    # resizeContainer returns since it's ok to be async and/or fail.
    resizeHandler = -> DockerUtils.resizeContainer container, options.stdout

    # We declare these in a scope outside of the RSVP.Promise callback so that we can reference
    # them from the finally to removeListener them. (They must be defined inside of the RSVP.Promise
    # callback to have access to the resolve / reject callbacks.)
    stdinCommandInterceptorHandler = null
    outputStreamEndHandler = null

    new RSVP.Promise (resolve, reject) ->
      # This handler fires first if we intercept a command from the container.
      stdinCommandInterceptorHandler = ({command}) ->
        options.stdinCommandInterceptor.stop()

        # We need to manually disconnect the output stream, or else Docker may keep it open,
        # causing doubled output if we reattach.
        outputStream.destroy()

        resolve {container, resolution: command}

      # This handler fires first if the container exits cleanly, is stopped/killed externally, or
      # its process ends and is restarted by the RestartPolicy.
      outputStreamEndHandler = ->
        options.stdinCommandInterceptor.stop()
        resolve {container, resolution: 'end'}

      options.stdinCommandInterceptor.on 'command', stdinCommandInterceptorHandler
      outputStream.on 'end', outputStreamEndHandler

      if options.stdout.isTTY
        outputStream.setEncoding 'utf8'

        # For TTY we have a blended output of both STDOUT and STDERR
        outputStream.pipe options.stdout, end: false

        resizeHandler()
        options.stdout.on 'resize', resizeHandler
      else
        outputStream.on 'end', ->
          try options.stdout.end() catch # ignore
          try options.stderr.end() catch # ignore

        # For non-TTY, we keep stdout and stderr separate, and pipe them appropriately to our
        # process's streams.
        container.modem.demuxStream outputStream, options.stdout, options.stderr

    .finally ->
      options.stdout.removeListener 'resize', resizeHandler
      options.stdinCommandInterceptor.removeListener 'command', stdinCommandInterceptorHandler
      outputStream.removeListener 'end', outputStreamEndHandler

updateCompletedServicesMap = (service, serviceConfig, containerInfo, completedServicesMap) ->
  completedServicesMap[service].containerName = containerInfo.Name

  exportedMounts = _.keys (containerInfo.Config.Volumes or {})
  exportedPaths = _.pick extractVolumesMap(containerInfo), exportedMounts

  # This will be a hash of "destination" paths (those inside the container) to
  # "source" paths in Docker's volume filesystems.
  completedServicesMap[service].volumePaths = exportedPaths

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
    volumePaths: null

  ensureImageAvailable docker, serviceConfig.image, options
  .then ({image, info: imageInfo}) ->
    ensureContainerConfigured docker, imageInfo, service, serviceConfig, options, completedServicesMap

  .then ({container, info: containerInfo}) ->
    # Attach before starting so we can be sure to get all of the output
    maybeAttachStream container, serviceConfig
    .then ({container, stream}) -> {container, stream, info: containerInfo}

  .then ({container, stream, info: containerInfo}) ->
    ensureContainerRunning container, containerInfo, service, serviceConfig, options
    .then ({container, info: containerInfo}) ->
      options.reporter.finish() unless options.leaveReporterOpen

      updateCompletedServicesMap service, serviceConfig, containerInfo, completedServicesMap

      forwarderReceipt = null

      maybeForwardPromise = if serviceConfig.localhost
        DockerUtils.inspectContainer container
        .then ({info}) ->
          # NetworkSettings.Ports looks like:
          # { '3080/tcp': [ { HostIp: '0.0.0.0', HostPort: '3080' } ],
          #   '3081/tcp': [ { HostIp: '0.0.0.0', HostPort: '49180' } ] }

          ports = []
          for source, outs of (containerInfo.NetworkSettings.Ports or {})
            ports.push parseInt(outs[0].HostPort)

          if ports.length
            forwarderReceipt = options.localhostForwarder.forward(ports)
      else
        RSVP.resolve()

      maybeForwardPromise
      .then ->
        pipeStreamsLoop container, stream, serviceConfig, options
      .finally ->
        forwarderReceipt.stop() if forwarderReceipt
    .then ({container, resolution}) -> {container, resolution}

# Calls maybePipeStdStreams and then loops to keep calling it if the stream ends while the
# container is still running. This lets us re-attach input and output streams when the container's
# process dies but is restarted by a RestartPolicy.
#
# Returns a promise that resolves to maybePipeStdStreams's container/resolution hash.
pipeStreamsLoop = (container, stream, serviceConfig, options) ->
  maybePipeStdStreams container, stream, options
  .then ({container, resolution}) ->
    if resolution is 'end'
      DockerUtils.inspectContainer container
      .then ({container, info}) ->
        # If the container is still going despite the stream having ended then we should try
        # to re-attach. It's likely that the container's RestartPolicy restarted the process.
        #
        # (The first call to maybeAttachStream happened before starting the service initially, back
        # in startService, which is why this call is down here and not at the beginning of
        # pipeStreamsLoop.)
        if info.State.Running or info.State.Restarting
          maybeAttachStream container, serviceConfig
          .then ({container, stream}) ->
            pipeStreamsLoop container, stream, serviceConfig, options
        else
          {container, resolution}
    else
      {container, resolution}

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
      'Binds': serviceConfig.binds

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

printDetachedMessage = (container, options) ->
  DockerUtils.inspectContainer(container)
  .then ({container, info}) ->
    # Docker reports names canonically as beginning with a '/', which looks lame. Remove it.
    name = info.Name.replace /^\//, ''

    options.reporter.message ''
    options.reporter.message ''
    options.reporter.message chalk.gray('Container detached: ') + chalk.bold(name)
    options.reporter.message chalk.gray('Reattach with: ') + "docker attach #{name}"
    options.reporter.message chalk.gray('Remove with: ') + "docker rm -fv #{name}"

# Gets the status code of a container, then removes it. Reports an error if the container did not
# exit cleanly with a code of 0.
#
# Resolves to a hash of the format:
#   container: the container
#   statusCode: if not null, the status code of the completed process
finalizeContainer = (container, options) ->
  DockerUtils.inspectContainer container
  .then ({container, info}) ->
    statusCode = info.State.ExitCode

    if statusCode? and statusCode isnt 0
      options.reporter.error "#{info.Config.Cmd.join ' '} failed with exit code #{statusCode}"

    # Since the process exited, we remove the container. (Equivalent of --rm in Docker.)
    DockerUtils.removeContainer container, { v: true }
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
    return RSVP.resolve({})

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
    primaryServiceConfig.containerVolumesFrom.push info.Name

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
#   freshlyCreated: true if the container was created this Galley run
#   volumePaths: map of container path -> host path for all volumes this container exports
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
      'as-service'
      'detach'
      'localhost'
      'publish-all'
      'repairSourceOwnership'
      'restart'
      'rsync'
      'unprotectStateful'
    ]
    alias:
      'add': 'a'
      'detach': 'd'
      'env': 'e'
      'publish-all': 'P'
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
    'unprotectStateful'
  ]

  # provide support for pulling these options from the galleycfg file.
  # Since minimist automatically fills in "false" for absent boolean flags,
  # we need to look and see if the flag was actually set in the args,
  # then decide whether or not to include it in options, allowing
  # settings in the gallleycfg file to be overriden by command line arguments.
  if '--rsync' in args
    _.merge options, _.pick argv, 'rsync'
  if '--repairSourceOwnership' in args
    _.merge options, _.pick argv, 'repairSourceOwnership'

  options.add = ServiceHelpers.normalizeMultiArgs argv.add
  options.source = path.resolve(argv.source) if argv.source

  if RECREATE_OPTIONS.indexOf(options.recreate) is -1
    throw "Unrecognized recreate option: '#{options.recreate}'"

  # Set up values to be merged in to the Galleyfile configuration for the primary service.
  serviceConfigOverrides =
    # Causes us to bind to stdin / stdout / stderr on starting up
    attach: true
    # Used to hold --volume values off the command line
    binds: []
    # List of containers to bring in volumes from. Not overlain on serviceConfig's volumesFrom
    # directly since that is a list of services that are started as pre-reqs, while these are
    # assumed to be containers.
    containerVolumesFrom: []
    env: {}
    # We will always want this service to be started completely fresh, to avoid any stale state
    forceRecreate: true
    # Also default to mapping this service's ports to the host
    publishPorts: true
    primary: true

  # The first element of argv._ is the service name, so if there's anything past that it means that
  # the user is specifying a command. In that case, we pull in that command, make the container
  # anonymous (so that it doesn't collide with a default version of the service already running),
  # and also don't publish ports to avoid collision. The --as-service flag disables the lack of
  # naming and port binding.
  if argv._.length > 1 and not argv['as-service']
    _.merge serviceConfigOverrides,
      command: argv._.slice(1)
      containerName: ''
      publishPorts: false
      restart: false

  _.merge serviceConfigOverrides, _.pick argv, [
    'entrypoint'
    'localhost'
    'user'
    'workdir'
  ]

  if argv['volumes-from']
    _.merge serviceConfigOverrides.containerVolumesFrom, ServiceHelpers.normalizeMultiArgs(argv['volumes-from'])

  if '--restart' in args
    _.merge serviceConfigOverrides, _.pick argv, 'restart'

  if '--publish-all' in args or '-P' in args
    serviceConfigOverrides.publishPorts = argv['publish-all']

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
      when 'unattached' then {statusCode: 0}

      when 'reload'
        options.reporter.message()
        options.reporter.message chalk.gray "#{chalk.bold 'Reload' } requested. Rechecking containers.\n"

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

      when 'detach'
        printDetachedMessage(container, options)
        .then -> {statusCode: null}

      when 'stop'
        DockerUtils.stopContainer container
        .then ->
          maybeRepairSourceOwnership docker, servicesConfig, service, options
        .then ->
          DockerUtils.removeContainer container
        .then ->
          # The official status code tends to be -1 when we stop the container forcefully, but
          # that looks weird so we fake it as a 0.
          {statusCode: 0}

      when 'end'
        maybeRepairSourceOwnership docker, servicesConfig, service, options
        .then ->
          finalizeContainer container, options
          .then ({statusCode}) -> {statusCode}

      else throw "UNKNOWN SERVICE RESOLUTION: #{resolution}"

  .catch (err) ->
    if err? and err isnt '' and typeof err is 'string' or err.json?
      message = (err?.json or (err if typeof err is 'string') or err?.message or 'Unknown error').trim()
      message = message.replace /^Error: /, ''
      options.reporter.error chalk.bold('Error:') + ' ' + message

    options.reporter.finish()
    options.stderr.write err?.stack if err?.stack

    {statusCode: -1}

module.exports = (args, commandOptions, done) ->
  {service, env, options, serviceConfigOverrides} = parseArgs(args)
  options = _.merge({}, commandOptions['globalOptions'], options)

  unless service? and not _.isEmpty(service)
    return help args, commandOptions, done

  docker = new Docker()

  options.stdin = commandOptions.stdin or process.stdin
  options.stderr = commandOptions.stderr or process.stderr
  options.stdout = commandOptions.stdout or new OverlayOutputStream(process.stdout)

  options.reporter = commandOptions.reporter or new ConsoleReporter(options.stderr)
  options.stdinCommandInterceptor = new StdinCommandInterceptor(options.stdin)

  options.localhostForwarder = new LocalhostForwarder(docker.modem, options.reporter)

  throw "Missing env for service #{service}. Format: <service>.<env>" unless env

  {globalConfig, servicesConfig} = ServiceHelpers.processConfig(commandOptions.config, env, options.add)

  primaryServiceConfig = servicesConfig[service]
  _.merge primaryServiceConfig, serviceConfigOverrides

  # We want to generate this before prepareServiceSource so that its potential modifications
  # to "volumesFrom" don't appear as additional prereq services.
  services = ServiceHelpers.generatePrereqServices(service, servicesConfig)

  sighupHandler = options.stdinCommandInterceptor.sighup.bind(options.stdinCommandInterceptor)
  process.on 'SIGHUP', sighupHandler

  prepareServiceSource docker, globalConfig, servicesConfig, service, env, options
  .then ({rsyncer}) ->
    go docker, servicesConfig, services, options
    .finally ->
      rsyncer?.stop()
  .then ({statusCode}) ->
    process.removeListener 'SIGHUP', sighupHandler
    options.stdinCommandInterceptor.stop()
    done statusCode
  .catch (err) ->
    console.error "UNCAUGHT EXCEPTION IN RUN COMMAND"
    console.error err
    console.error err?.stack if err?.stack
    process.exit 255

# Exposed for unit testing
module.exports.parseArgs = parseArgs
