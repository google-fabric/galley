_ = require 'lodash'
expect = require 'expect'
RSVP = require 'rsvp'

testCommands = require './test_commands'

####################################################################################################
# Acceptance tests for Galley.
#
# These tests work with a small set of containers that show off the primary capabilities of
# Galley. The "application" container links to "backend", and its command is to curl backend.
# backend runs a tiny webserver that outputs JSON of a local file, a file mapped from a volume
# container ("config"), and an HTTP request to another container, "database".
#
# This setup means that we can check the JSON output of application and see that 2 levels of link
# and one volume container are connected correctly.
#
# We use a custom "TestReporter" on the run command to see what tasks Galley performed for each of
# the services (e.g. Creating, Restarting)
####################################################################################################


ENV = 'galley-integration'

# This is what we expect from application when it curls to service and gets data.
APPLICATION_SUCCESS =
  index: 'Hello, World!\n'
  config:
    config: "ok"
  database:
    data: "ok"

# We tag from ":original" to ":latest" so that we can eventually update "latest"
# to test the staleness behavior.
resetTags = ->
  RSVP.all([
    testCommands.exec 'docker tag galley-integration-backend:original galley-integration-backend'
    testCommands.exec 'docker tag galley-integration-database:original galley-integration-database'
    testCommands.exec 'docker tag galley-integration-application:original galley-integration-application'
    testCommands.exec 'docker tag galley-integration-config:original galley-integration-config'
    testCommands.exec 'docker tag galley-integration-rsync:original galley-integration-rsync'
  ])

removeContainers = ->
  testCommands.exec "docker rm -v backend.#{ENV} database.#{ENV} config.#{ENV}"

describe 'galley', ->
  @timeout 15000

  # To establish a baseline, we first start up all the services, then stop them. This means that
  # each test run should have a consistent starting place.
  before ->
    @timeout 0

    resetTags()
    .then ->
      testCommands.run ['-a', 'backend-addon', "application.#{ENV}"]
    .then ->
      testCommands.stopEnv ENV

  afterEach ->
    @timeout 0

    testCommands.stopEnv ENV
    .then ->
      resetTags()

  after ->
    @timeout 0

    testCommands.stopEnv ENV
    .then ->
      removeContainers()

  describe 'cleanup', ->
    it 'removes everything except stateful', ->
      testCommands.cleanup()
      .then ({reporter}) ->
        expect(reporter.services).toEqual
          'backend.galley-integration': ['Removing']
          'database.galley-integration': ['Preserving stateful service']
          'config.galley-integration': ['Removing']

      .finally ->
        # Need to put things back to how the "before" block sets things up so that the next set
        # of tests can run.
        testCommands.run ['-a', 'backend-addon', "application.#{ENV}"]
        .then ->
          testCommands.stopEnv ENV

  describe 'list', ->
    it 'prints addons and services with environments', ->
      testCommands.list()
      .then ({out}) ->
        expect(out).toEqual '''
Galleyfile: ./Galleyfile.js
  application -a backend-addon
  backend [.galley-integration]
  config
  database

'''

  describe 'basics', ->
    # Base test to show that we're starting everything up correctly.
    it 'starts up prereq services', ->
      testCommands.run ['-a', 'backend-addon', "application.#{ENV}"]
      .then ({stdout, reporter}) ->
        expect(JSON.parse(stdout)).toEqual APPLICATION_SUCCESS

        expect(reporter.services).toEqual
          'config': ['Checking', 'Starting']
          'database': ['Checking', 'Starting']
          'backend': ['Checking', 'Starting']
          'application': ['Checking', 'Creating', 'Starting']

    # Starts everything twice to show that the containers still running are just checked and
    # preserved.
    it 'preserves running services', ->
      testCommands.run ['-a', 'backend-addon', "application.#{ENV}"]
      .then ->
        testCommands.run ['-a', 'backend-addon', "application.#{ENV}"]
      .then ({stdout, reporter}) ->
        expect(JSON.parse(stdout)).toEqual APPLICATION_SUCCESS

        expect(reporter.services).toEqual
          'config': ['Checking', 'Starting']  # As a volume container, is never still running
          'database': ['Checking']
          'backend': ['Checking']
          'application': ['Checking', 'Creating', 'Starting']

  describe 'commands', ->
    it 'allows source, entrypoint, and new command', ->
      testCommands.run ['--entrypoint', 'cat', '-s', 'acceptance/fixtures/src', "application.#{ENV}", '/src/code.txt']
      .then ({stdout, stderr, reporter}) ->
        expect(stdout).toEqual "println 'Hello World!'\n"

    it 'sets env variables, pipes stdin through correctly', ->
      testCommands.run ['-e', 'COUNT_CMD=/usr/bin/wc', "application.#{ENV}", '/bin/sh', '-c', '$COUNT_CMD'], stdin: 'kittens puppies'
      .then ({stdout, reporter}) ->
        expect(stdout).toEqual '      0       2      15\n'

  describe 'links', ->
    # If a container was deleted, it is created.
    it 'creates removed linked-to services', ->
      testCommands.exec "docker rm -f backend.#{ENV}"
      .then ->
        testCommands.run ['-a', 'backend-addon', "application.#{ENV}"]
      .then ({stdout, reporter}) ->
        expect(JSON.parse(stdout)).toEqual APPLICATION_SUCCESS

        expect(reporter.services).toEqual
          'config': ['Checking', 'Starting']
          'database': ['Checking', 'Starting']
          'backend': ['Checking', 'Creating', 'Starting']
          'application': ['Checking', 'Creating', 'Starting']

    # If a container's link is missing, that container is created, and then linking container is
    # *re*-created to pick up a link to the new container.
    it 'recreates services with removed linked-to services', ->
      testCommands.exec "docker rm -f database.#{ENV}"
      .then ->
        testCommands.run ['-a', 'backend-addon', "application.#{ENV}"]
      .then ({stdout, reporter}) ->
        expect(JSON.parse(stdout)).toEqual APPLICATION_SUCCESS

        expect(reporter.services).toEqual
          'config': ['Checking', 'Starting']
          'database': ['Checking', 'Creating', 'Starting']
          'backend': ['Checking', 'Removing', 'Creating', 'Starting']
          'application': ['Checking', 'Creating', 'Starting']

    # Test that if the 'backend' service is already running that it gets linked to for
    # application, rather than recreated. We map source over to an alternate directory
    # so that we can see in application that it's actually contacting this service we
    # hand-started.
    it 'uses existing backend container', ->
      testCommands.run ['-s', 'acceptance/fixtures/public', '--rsync', '--detach', "backend.#{ENV}"]
      .then ({stdout, reporter}) ->
        # FWIW sometimes this fails due to failures in previous runs of the tests
        # preventing containers from being removed consistently. If that's the case,
        # a second run of this test should make things right.
        expect(reporter.services).toEqual
          'backend (rsync)': ['Checking', 'Creating', 'Starting', 'Syncing']
          'config': ['Checking', 'Starting']
          'database': ['Checking', 'Starting']
          'backend': ['Checking', 'Removing', 'Creating', 'Starting']

        testCommands.run ['-a', 'backend-addon', "application.#{ENV}"]
      .then ({stdout, reporter}) ->
        expect(JSON.parse(stdout)).toEqual _.merge {}, APPLICATION_SUCCESS,
          index: 'Hello, Source!\n'

        expect(reporter.services).toEqual
          'config': ['Checking', 'Starting']
          'database': ['Checking']
          'backend': ['Checking']
          'application': ['Checking', 'Creating', 'Starting']
      .finally ->
        testCommands.exec 'docker rm -vf backend.galley-integration-rsync'

        # Go back to the container without the mounted source to avoid polluting other tests
        testCommands.run ['--detach', "backend.#{ENV}"]

  describe 'volumes', ->
    it 'recreates after volume is deleted', ->
      testCommands.exec "docker rm -f config.#{ENV}"
      .then ->
        testCommands.run ['-a', 'backend-addon', "application.#{ENV}"]
      .then ({stdout, reporter}) ->
        expect(JSON.parse(stdout)).toEqual APPLICATION_SUCCESS

        expect(reporter.services).toEqual
          'config': ['Checking', 'Creating', 'Starting']
          'database': ['Checking', 'Starting']
          'backend': ['Checking', 'Removing', 'Creating', 'Starting']
          'application': ['Checking', 'Creating', 'Starting']
