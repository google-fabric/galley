tcpProxy = require 'tcp-proxy'

# Class to run TCP proxies from the localhost in to a boot2docker VM. Useful for when you need
# devices outside of the host machine to connect in to a container.
class LocalhostForwarder
  constructor: (dockerConfig, reporter) ->
    @dockerConfig = dockerConfig
    @reporter = reporter

  # Returns either a receipt object with a "stop" method, or null if forwarding is
  # unnecessary.
  #
  # ports: array of port numbers that are expected to be exposed on the Docker host,
  #   which we will expose on the Galley host.
  forward: (ports) ->
    # If we're connecting to Docker via socket, assume that containers are running on the same host
    # as Galley, so there's no need to forward.
    return if @dockerConfig.socketPath?

    servers = for port in ports
      server = tcpProxy.createServer
        target: 
          host: @dockerConfig.host
          port: port

      server.listen port

      # "do" shenanigans since "port" mutates inside the loop.
      server.on 'error', do (port) =>
        (err) => @reporter.error "Failure proxying to #{@dockerConfig.host}:#{port}: #{err}"

      server

    new LocalhostForwarderReceipt(servers)

class LocalhostForwarderReceipt
  constructor: (servers) ->
    @servers = servers

  stop: ->
    server.close() for server in @servers
    @servers = []

module.exports = LocalhostForwarder
