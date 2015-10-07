var DockerArgs, _, expect;

expect = require('expect');

_ = require('lodash');

DockerArgs = require('../lib/lib/docker_args');

describe('DockerArgs', function() {
  describe('formatEnvVariables', function() {
    it('should be a list for Docker', function() {
      var envVars;
      envVars = {
        'VAR1': 'value1',
        'VAR2': 'value2'
      };
      return expect(DockerArgs.formatEnvVariables(envVars)).toEqual(['VAR1=value1', 'VAR2=value2']);
    });
    return it('excludes nulls but includes empty strings', function() {
      var envVars;
      envVars = {
        'VAR1': '',
        'VAR2': null
      };
      return expect(DockerArgs.formatEnvVariables(envVars)).toEqual(['VAR1=']);
    });
  });
  describe('formatLinks', function() {
    return it('should format links, looking up container names', function() {
      var containerNames, links;
      links = ['mongo', 'project-service-mysql:mysql'];
      containerNames = {
        'mongo': 'mongo.dev',
        'project-service-mysql': 'thundering_tesla'
      };
      return expect(DockerArgs.formatLinks(links, containerNames)).toEqual(['mongo.dev:mongo', 'thundering_tesla:mysql']);
    });
  });
  describe('formatPortBindings', function() {
    return it('should return portBindings and exposedPorts', function() {
      var ports;
      ports = ['3200:3000', '8506'];
      return expect(DockerArgs.formatPortBindings(ports)).toEqual({
        portBindings: {
          '3000/tcp': [
            {
              'HostPort': '3200'
            }
          ]
        },
        exposedPorts: {
          '8506/tcp': {}
        }
      });
    });
  });
  describe('formatVolumes', function() {
    return it('should return volumes', function() {
      var volumes;
      volumes = ['/kittens', '/etc/puppies'];
      return expect(DockerArgs.formatVolumes(volumes)).toEqual({
        '/kittens': {},
        '/etc/puppies': {}
      });
    });
  });
  return describe('formatVolumesFrom', function() {
    return it('looks up some services but not others', function() {
      var containerNames, volumesFrom;
      volumesFrom = ['srv-config', 'www.rsync'];
      containerNames = {
        'srv-config': 'srv-config.dev'
      };
      return expect(DockerArgs.formatVolumesFrom(volumesFrom, containerNames)).toEqual(['srv-config.dev', 'www.rsync']);
    });
  });
});
