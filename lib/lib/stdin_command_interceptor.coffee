# Class to manage piping from stdin into a container while listening for CTRL-P CTRL-... commands.
#
# Commands are:
#
#  CTRL-Q: Detach the container. Docker can handle this by itself, but now that we're trapping
#    CTRL-P we do this ourselves.
#  CTRL-R: Reload Galley. Also happens if you send a SIGHUP to the process. Causes Galley to run
#    through checking all the containers as if it were just started.
#  CTRL-C: Stop the container. Useful for when you have a RestartPolicy that is causing an app to
#    reload itself on CTRL-C, but you actually really do want to stop the container.
#  CTRL-P: Passes a CTRL-P through to the stream.

events = require 'events'

CTRL_C = '\u0003'
CTRL_P = '\u0010'
CTRL_Q = '\u0011'
CTRL_R = '\u0012'

class StdinCommandInterceptor extends events.EventEmitter
  constructor: (stdin) ->
    @stdin = stdin

    # We create a bound instance of this method so that we can removeListener it.
    @stdinDataHandler = @onStdinData.bind(@)

  # Pipes data from the STDIN given to this instance's constructor through to the inputStream. If
  # STDIN is a TTY, intercepts control sequences to close itself and trigger a resolution.
  start: (inputStream) ->
    @inputStream = inputStream
    @previousKey = null

    if @stdin.isTTY
      @stdin.setRawMode true

      @inputStream.setEncoding 'utf8'
      @stdin.setEncoding 'utf8'

      @stdin.on 'data', @stdinDataHandler
    else
      @stdin.pipe @inputStream

    # We dig into Dockerode's internal data to get the socket because it's the only reliable way
    # to detect the close, for example if the container restarts or shuts down unexpectedly.
    #
    # Reasons why the socket to STDIN closes:
    #  - Someone called #stop on us, which caused us to destroy the @inputStream. This tends to
    #    happen after we have already triggered a command (see Run command's maybePipeStdStreams)
    #    so we don't want to trigger anything additional. In this case, @inputStream will have
    #    already been set to null.
    #  - Our own STDIN has EOF'd (e.g. it was piped in from a local file). In this case, @stdin
    #    will no longer be "readable". We don't trigger a command here, either, because we assume
    #    that the consumer in the container will react to the EOF, finish its task, and close the
    #    output stream. (Reacting too early to EOF creates a race condition where we would terminate
    #    before the container's process wrote all of its output.)
    #  - Docker has detached and left the container running. This used to be do-able by pressing
    #    CTRL-P CTRL-Q before we trapped it for our own purposes, but in case it is possible through
    #    some other means we detect it and trigger a 'detach' command to notify our listeners and
    #    keep them from thinking that the RestartPolicy triggered and they should re-attach.
    @inputStream._output.socket.on 'close', =>
      @_trigger 'detach' if @inputStream and @stdin.readable

  stop: ->
    return unless @inputStream

    # Set our @inputStream to null up front so that when the inputStream is destroyed and its
    # socket closes we know not to trigger the 'detach' from the handler above.
    inputStream = @inputStream
    @inputStream = null

    inputStream.destroy()

    if @stdin.isTTY
      @stdin.removeListener 'data', @stdinDataHandler
      @stdin.setRawMode false
    else
      @stdin.unpipe inputStream

  # Looks at each keystroke to check and see if the user is doing a CTRL-P escape sequence. If so,
  # traps it to potentially resolve the command. Otherwise passes the value through.
  onStdinData: (key) ->
    if @previousKey is CTRL_P
      @previousKey = null
      switch key
        when CTRL_C then @_trigger 'stop'
        when CTRL_P then @inputStream.write(CTRL_P)
        when CTRL_Q then @_trigger 'detach'
        when CTRL_R then @_trigger 'reload'
    else
      @previousKey = key
      @inputStream.write(key)

  # Called from outside by a SIGHUP handler. Has the same effect as CTRL-P CTRL-R, which causes
  # Galley to recheck all containers.
  sighup: -> @_trigger 'reload'

  _trigger: (command) -> @emit 'command', {command}

module.exports = StdinCommandInterceptor
