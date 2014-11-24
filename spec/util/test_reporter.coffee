chalk = require 'chalk'

# Test double for the "ConsoleReporter" class that keeps track of what
# "tasks" were called for each service, in order. Makes it easy for the
# acceptance tests to determine what Galley did when starting up a
# service.
class TestReporter
  constructor: ->
    @services = {}
    @currentService = null

  startService: (serviceName) ->
    @currentService = serviceName
    @services[@currentService] = []
    @

  startTask: (job) ->
    @lastTask = job
    @

  startProgress: ->
    {
      set: ->
      clear: ->
    }

  succeedTask: (msg = 'done!') ->
    @services[@currentService].push @lastTask
    @lastTask = null
    @

  completeTask: (msg) ->
    @services[@currentService].push @lastTask
    @lastTask = null
    @

  finish: ->
    if @lastTask
      @services[@currentService].push @lastTask

    @currentService = null
    @lastTask = null
    @

  error: (err) ->
    @currentService = null
    @lastTask = null
    @lastError = err
    @

  message: (msg) ->
    @currentService = null
    @lastTask = null
    @

module.exports = TestReporter
