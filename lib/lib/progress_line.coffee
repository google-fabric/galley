spin = require 'term-spinner'

# Class to wrap state of a string written to an output stream, so that it can be cleared and
# overwritten by a new string.
module.exports =
  class ProgressLine
    constructor: (@stream, @colorFn = (v) -> v) ->
      @spinner = spin.new()
      @currentStr = ''

    set: (str) ->
      unless @stream.isTTY
        return @stream.write str

      @spinner.next()

      @stream.moveCursor(-@currentStr.length, 0)
      @currentStr = @currentStr.trim()

      nextStr = if str?[0] is '[' then str else "#{@spinner.current} #{str}"

      if @currentStr.length > nextStr.length
        nextStr = nextStr + Array(@currentStr.length - nextStr.length + 1).join ' '

      @stream.write @colorFn(nextStr)
      @currentStr = nextStr

    clear: ->
      return unless @stream.isTTY

      @set ''
      @stream.moveCursor(-@currentStr.length - 1, 0)
