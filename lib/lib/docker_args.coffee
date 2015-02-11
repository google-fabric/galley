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

# Given a list of ports of the form "<container>:<host>" or just "<container>", returns a hash of
# portBindings and exposedPorts. portBindings maps to specific ports on the host, whereas
# exposedPorts will cause Docker to map to random ports on the host.
#
# These go into the HostConfig.Ports and ExposedPorts keys for container creation, respectively.
formatPortBindings = (ports) ->
  portBindings = {}
  exposedPorts = {}

  for port in ports
    [src, dst] = port.split(':')
    if dst
      portBindings["#{src}/tcp"] = [{'HostPort': dst}]
    else
      exposedPorts["#{src}/tcp"] = {}

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
