charm = require 'charm'
stream = require 'stream'

# Wrapper for an output stream (e.g. stdout) that adds an "overlay" in the lower right hand
# corner. Overlay can show a "status" (consistent, purple on white) or a "flash" (goes away after
# a few seconds, white on purple).
#
# Attaching to a non-TTY stream will cause this to pass data through with no modifications.
#
# Not entirely great at what happens when STDOUT lines wrap or the terminal is resized: sometimes
# the overlay will not get erased completely. It seems to work well enough in practice, however.
class OverlayOutputStream extends stream.Writable
  constructor: (@stream, options) ->
    super options
    @charm = charm(@stream)
    @isTTY = @stream.isTTY
    @statusMessage = ''

    # TODO(phopkins): Could try to detect here when the window gets narrower,
    # causing us to wrap.
    @stream.on 'resize', @writeOverlay.bind(@)

  # Sets a message that permanently sits in the lower-right as the stream
  # scrolls by behind it.
  setOverlayStatus: (status) ->
    @statusMessage = status
    if @hasOverlay
      @writeOverlay()

  # Pops a message up (over the status) for a few seconds, then disappears (and
  # status, if any, re-appears).
  flashOverlayMessage: (message) ->
    if @unsetFlashTimeout
      clearTimeout @unsetFlashTimeout

    @unsetFlashTimeout = setTimeout @unsetOverlayFlash.bind(@), 2000
    @flashMessage = message
    @writeOverlay()

  unsetOverlayFlash: ->
    @flashMessage = null
    @writeOverlay()

  clearOverlay: -> 
    if @hasOverlay
      @charm.erase('end') 
      @charm.erase('down')

  writeOverlay: ->
    return unless @isTTY

    @clearOverlay()
    @charm.push(true)

    if @flashMessage
      text = @flashMessage
      @charm.background(13)
      @charm.foreground('white')
    else if @statusMessage
      @charm.foreground(13)
      @charm.background('white')
      text = @statusMessage
    else
      @charm.pop(true)
      return

    text = " #{text} " if text

    @charm.position(@stream.columns - text.length, @stream.rows)
    @charm.write(text)
    @charm.pop(true)
    @hasOverlay = true

  # Proxy our writes through to the underlying stream, wrapped in
  # making our status disappear and re-appear.
  _write: (chunk, encoding, cb) ->
    @clearOverlay()
    ret = @stream.write chunk, encoding, cb
    @writeOverlay()
    ret

  end: ->
    @clearOverlay()
    super

module.exports = OverlayOutputStream
