fs = require 'fs'
path = require 'path'
url = require 'url'
_ = require 'lodash'
homeDir = require 'home-dir'

module.exports =
  connectionConfig: ->
    hostUrl = url.parse process.env.DOCKER_HOST or ''

    dockerOpts = if hostUrl.hostname
      host: hostUrl.hostname
      port: hostUrl.port
    else
      socketPath: process.env.DOCKER_HOST or '/var/run/docker.sock'

    if (certPath = process.env.DOCKER_CERT_PATH)
      _.merge dockerOpts,
        protocol: 'https'
        ca: fs.readFileSync "#{certPath}/ca.pem"
        cert: fs.readFileSync "#{certPath}/cert.pem"
        key: fs.readFileSync "#{certPath}/key.pem"

    dockerOpts

  # Checks the user's .dockercfg file for login information. .dockercfg is a JSON hash, keyed by
  # registry host name. Within the host's config is an 'auth' key whose value is base64-encoded
  # "username:password" for the server.
  authConfig: (host) ->
    hostConfig = try
      configFile = fs.readFileSync path.resolve(homeDir(), '.dockercfg')
      config = JSON.parse configFile.toString()
      config[host]
    catch e
      # If file doesn't exist don't explode, just don't have auth
      throw e unless e?.code is 'ENOENT'

    if hostConfig?
      authBuffer = new Buffer hostConfig.auth, 'base64'
      [username, password] = authBuffer.toString().split ':'

      username: username
      password: password
      serveraddress: host
