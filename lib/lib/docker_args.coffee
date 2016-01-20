# Helpers for converting our config format into arguments to pass to Docker's API

_ = require 'lodash'

# Formats a hash of env variable name to value to the array of VAR=VALUE strings Docker expects
formatEnvVariables = (envVars) ->
  out = []
  for name, value of envVars
    out.push "#{name}=#{value}" if value?
  out

# given links for a single service from the config file
# and a map of service -> container name
# generate the Link option for the Docker API
formatLinks = (links, containerNameMap) ->
  for link in links
    service = link.split(':')[0]
    alias = link.split(':')[1] or service
    containerName = containerNameMap[service]
    "#{containerName}:#{alias}"

# Given a list of ports of the form "<host>:<container>" or just "<container>", returns a hash of
# portBindings and exposedPorts. We always expose every port specified so we can map ports
# regardless of EXPOSE commands in the Dockerfile.
#
# These go into the HostConfig.Ports and ExposedPorts keys for container creation, respectively.
formatPortBindings = (ports) ->
  portBindings = {}
  exposedPorts = {}

  for port in ports
    [dst, src] = port.split(':')
    [src, protocol] = if src? && src.indexOf('/') > 0 then src.split('/') else [src, 'tcp']
    unless src?
      src = dst
      dst = null

    # If dst is null then Docker will allocate an unused port
    portBindings["#{src}/#{protocol}"] = [{'HostPort': dst}]
    exposedPorts["#{src}/#{protocol}"] = {}

  {portBindings, exposedPorts}

# Formats the container option for exported volumes. The format for the create endpoint is a hash of:
#   <path>: {}
formatVolumes = (volumes) ->
  _.zipObject _.map volumes, (volume) -> [volume, {}]

# Formats the VolumesFrom parameter, which doesn't need much formatting. It looks up service names
# in the containerNameMap, but if a name is missing it assumes it's a container name. This
# assumption is necessary for passing in the rsync source container name without faking it as a
# service in containerNameMap.
formatVolumesFrom = (volumesFrom, containerNameMap) ->
  for name in volumesFrom
    containerNameMap[name] or name

module.exports = {
  formatEnvVariables
  formatLinks
  formatPortBindings
  formatVolumes
  formatVolumesFrom
}
