expect = require 'expect'
_ = require 'lodash'

DockerArgs = require '../lib/lib/docker_args'

# Small regression-like tests to make sure we retain the right formatting.

describe 'DockerArgs', ->
  describe 'formatEnvVariables', ->
    it 'should be a list for Docker', ->
      envVars =
        'VAR1': 'value1'
        'VAR2': 'value2'

      expect(DockerArgs.formatEnvVariables(envVars)).toEqual ['VAR1=value1', 'VAR2=value2']

    it 'excludes nulls but includes empty strings', ->
      envVars =
        'VAR1': ''
        'VAR2': null

      expect(DockerArgs.formatEnvVariables(envVars)).toEqual ['VAR1=']

  describe 'formatLinks', ->
    it 'should format links, looking up container names', ->
      links = ['mongo', 'project-service-mysql:mysql']
      containerNames =
        'mongo': 'mongo.dev'
        'project-service-mysql': 'thundering_tesla'

      expect(DockerArgs.formatLinks(links, containerNames)).toEqual [
        'mongo.dev:mongo'
        'thundering_tesla:mysql'
      ]

  describe 'formatPortBindings', ->
    it 'should return portBindings and exposedPorts', ->
      ports = ['3200:3000', '8506', '5555:4444/udp']
      expect(DockerArgs.formatPortBindings(ports)).toEqual
        portBindings: {'3000/tcp': [{'HostPort': '3200'}], '8506/tcp': [{'HostPort': null}], '4444/udp': [{'HostPort': '5555'}]}
        exposedPorts: {'3000/tcp': {}, '8506/tcp': {}, '4444/udp': {}}

  describe 'formatVolumes', ->
    it 'should return volumes', ->
      volumes = ['/kittens', '/etc/puppies']
      expect(DockerArgs.formatVolumes(volumes)).toEqual
        '/kittens': {}
        '/etc/puppies': {}

  describe 'formatVolumesFrom', ->
    it 'looks up some services but not others', ->
      volumesFrom = ['srv-config', 'www.rsync']
      containerNames =
        'srv-config': 'srv-config.dev'

      expect(DockerArgs.formatVolumesFrom(volumesFrom, containerNames)).toEqual [
        'srv-config.dev'
        'www.rsync'
      ]
