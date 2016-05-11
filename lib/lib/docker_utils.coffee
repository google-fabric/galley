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

removeImage = (image, opts = {}) ->
  new RSVP.Promise (resolve, reject) ->
    image.remove opts, (err) ->
      if err then reject(err) else resolve()

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
    #
    # If there's no ".", we look up auth anyway in the case of private repos on hub.docker.com.
    if imageName.indexOf('/') isnt -1
      repository = imageName.split('/')[0]
      opts.authconfig = if repository.indexOf('.') isnt -1
        authConfigFn(repository)
      else
        authConfigFn()

    docker.pull imageName, opts, (err, stream) ->
      return reject(err) if err

      stream.on 'data', (byteBuffer) ->
        # Docker sends along a nice summary of the download progress, including an ASCII progress
        # bar and estimation of time remaining for the current download. Send that along to our
        # progress callback.
        #
        # At least with Docker 1.11 running in Docker for Mac, the byteBuffer can contain more than
        # one newline-separated JSON object, so we split, look for errors across all of them, and
        # report on the first one.
        #
        # TODO(finneganh): Do better about multiple simultaneous statuses
        statusArr = byteBuffer.toString().split('\n').filter((str) -> str.length).map((json) -> JSON.parse(json))
        statusArr.forEach (status) ->
          reject(status.error) if status.error?

        progressCb statusArr[0].progress or statusArr[0].status

      stream.on 'end', -> resolve()

listContainers = (docker, opts = {}) ->
  new RSVP.Promise (resolve, reject) ->
    docker.listContainers opts, (err, infos) ->
      if err then reject(err) else resolve({infos})

listImages = (docker, opts = {}) ->
  new RSVP.Promise (resolve, reject) ->
    docker.listImages opts, (err, infos) ->
      if err then reject(err) else resolve({infos})

module.exports = {
  inspectImage
  removeImage
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
  listContainers
  listImages
}
