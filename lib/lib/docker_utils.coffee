url = require 'url'
_ = require 'lodash'
RSVP = require 'rsvp'

# Series of wrappers around Dockerode methods to turn them in to RSVP promises. The convention is
# for the promise to resolve to a hash with a "container" key and optionally a key relating to the
# result of the method (e.g. "info", "stream").

# Resolves to image and info
inspectImage = (image) ->
  new RSVP.Promise (resolve, reject) ->
    image.inspect (err, info) ->
      if err then reject(err) else resolve({image, info})

createContainer = (docker, opts) ->
  new RSVP.Promise (resolve, reject) ->
    docker.createContainer opts, (err, container) ->
      if err then reject(err) else resolve({container})

# Resolves to container and info
inspectContainer = (container) ->
  new RSVP.Promise (resolve, reject) ->
    container.inspect (err, info) ->
      if err then reject(err) else resolve({container, info})

startContainer = (container, opts = {}) ->
  new RSVP.Promise (resolve, reject) ->
    container.start opts, (err) ->
      if err then reject(err) else resolve({container})

stopContainer = (container, opts = {}) ->
  new RSVP.Promise (resolve, reject) ->
    container.stop opts, (err) ->
      if err then reject(err) else resolve({container})

restartContainer = (container, opts = {}) ->
  new RSVP.Promise (resolve, reject) ->
    container.restart opts, (err) ->
      if err then reject(err) else resolve({container})

pauseContainer = (container, opts = {}) ->
  new RSVP.Promise (resolve, reject) ->
    container.pause opts, (err) ->
      if err then reject(err) else resolve({container})

unpauseContainer = (container, opts = {}) ->
  new RSVP.Promise (resolve, reject) ->
    container.unpause opts, (err) ->
      if err then reject(err) else resolve({container})

# Resolves to container and stream
attachContainer = (container, opts) ->
  new RSVP.Promise (resolve, reject) ->
    container.attach opts, (err, stream) ->
      if err then reject(err) else resolve({container, stream})

# Resolves to container and completion result
waitContainer = (container) ->
  new RSVP.Promise (resolve, reject) ->
    container.wait (err, result) ->
      if err then reject(err) else resolve({container, result})

removeContainer = (container, opts) ->
  new RSVP.Promise (resolve, reject) ->
    container.remove opts, (err) ->
      if err then reject(err) else resolve()

resizeContainer = (container, ttyStream) ->
  new RSVP.Promise (resolve, reject) ->
    dimensions =
      h: ttyStream.rows
      w: ttyStream.columns

    if dimensions.h? and dimensions.w?
      container.resize dimensions, (err) ->
        if err then reject(err) else resolve({container})
    else
      resolve({container})

# Downloads the image by name and returns a promise that will resolve when it's complete. Periodically
# calls the progressCb function with either undefined or an interesting progress string.
#
# Does not resolve to a value.
downloadImage = (docker, imageName, authConfigFn, progressCb = ->) ->
  new RSVP.Promise (resolve, reject) ->
    opts = {}

    # Check and see if we're trying to do "repository/image" and, if the repository has a "." in
    # it, grab the credentials. The "." check is the same that the docker command line / tool uses
    # to decide whether the repository is a remote server vs. on its default hub.docker.com registry.
    if imageName.indexOf('/') isnt -1
      repository = imageName.split('/')[0]
      if repository.indexOf('.') isnt -1
        opts.authconfig = authConfigFn(repository)

    docker.pull imageName, opts, (err, stream) ->
      return reject(err) if err

      stream.on 'data', (byteBuffer) ->
        # Docker sends along a nice summary of the download progress, including an ASCII progress
        # bar and estimation of time remaining for the current download. Send that along to our
        # progress callback.
        resp = JSON.parse byteBuffer.toString()
        reject(resp.error) if resp.error?

        progressCb resp.progress or resp.status

      stream.on 'end', -> resolve()

module.exports = {
  inspectImage
  createContainer
  inspectContainer
  startContainer
  stopContainer
  restartContainer
  pauseContainer
  unpauseContainer
  attachContainer
  resizeContainer
  waitContainer
  removeContainer
  downloadImage
}
