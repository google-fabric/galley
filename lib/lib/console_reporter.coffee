chalk = require 'chalk'

ProgressLine = require './progress_line'

class ConsoleReporter
  constructor: (@stream) ->
    @inLine = false

  maybeSpace: ->
    if @inLine
      @stream.write ' '

  startService: (serviceName) ->
    @stream.write chalk.blue(serviceName + ':')
    @inLine = true
    @

  startTask: (job) ->
    @maybeSpace()
    @stream.write chalk.gray(job + '…')
    @inLine = true
    @

  startProgress: ->
    @maybeSpace()
    new ProgressLine @stream, chalk.gray

  succeedTask: (msg = 'done!') ->
    @maybeSpace()
    @stream.write chalk.green(msg)
    @

  completeTask: (msg) ->
    @maybeSpace()
    @stream.write chalk.cyan(msg)
    @

  finish: ->
    if @inLine
      @stream.write '\n'
    @inLine = false
    @

  error: (err) ->
    @maybeSpace()
    @stream.write chalk.red(err) + '\n'
    @inLine = false
    @

  message: (msg = '') ->
    @stream.write msg + '\n'
    @inLine = false
    @

module.exports = ConsoleReporter
