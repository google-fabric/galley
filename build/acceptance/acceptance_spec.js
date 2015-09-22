var APPLICATION_SUCCESS, ENV, RSVP, _, expect, removeContainers, resetTags, testCommands;

_ = require('lodash');

expect = require('expect');

RSVP = require('rsvp');

testCommands = require('./test_commands');

ENV = 'galley-integration';

APPLICATION_SUCCESS = {
  index: 'Hello, World!\n',
  config: {
    config: "ok"
  },
  database: {
    data: "ok"
  }
};

resetTags = function() {
  return RSVP.all([testCommands.exec('docker tag -f galley-integration-backend:original galley-integration-backend'), testCommands.exec('docker tag -f galley-integration-database:original galley-integration-database'), testCommands.exec('docker tag -f galley-integration-application:original galley-integration-application'), testCommands.exec('docker tag -f galley-integration-config:original galley-integration-config'), testCommands.exec('docker tag -f galley-integration-rsync:original galley-integration-rsync')]);
};

removeContainers = function() {
  return testCommands.exec("docker rm -v backend." + ENV + " database." + ENV + " config." + ENV);
};

describe('galley', function() {
  this.timeout(15000);
  before(function() {
    this.timeout(0);
    return resetTags().then(function() {
      return testCommands.run(['-a', 'backend-addon', "application." + ENV]);
    }).then(function() {
      return testCommands.stopEnv(ENV);
    });
  });
  afterEach(function() {
    this.timeout(0);
    return testCommands.stopEnv(ENV).then(function() {
      return resetTags();
    });
  });
  after(function() {
    this.timeout(0);
    return testCommands.stopEnv(ENV).then(function() {
      return removeContainers();
    });
  });
  describe('cleanup', function() {
    return it('removes everything except stateful', function() {
      return testCommands.cleanup().then(function(arg) {
        var reporter;
        reporter = arg.reporter;
        return expect(reporter.services).toEqual({
          'backend.galley-integration': ['Removing'],
          'database.galley-integration': ['Preserving stateful service'],
          'config.galley-integration': ['Removing']
        });
      })["finally"](function() {
        return testCommands.run(['-a', 'backend-addon', "application." + ENV]).then(function() {
          return testCommands.stopEnv(ENV);
        });
      });
    });
  });
  describe('basics', function() {
    it('starts up prereq services', function() {
      return testCommands.run(['-a', 'backend-addon', "application." + ENV]).then(function(arg) {
        var reporter, stdout;
        stdout = arg.stdout, reporter = arg.reporter;
        expect(JSON.parse(stdout)).toEqual(APPLICATION_SUCCESS);
        return expect(reporter.services).toEqual({
          'config': ['Checking', 'Starting'],
          'database': ['Checking', 'Starting'],
          'backend': ['Checking', 'Starting'],
          'application': ['Checking', 'Creating', 'Starting']
        });
      });
    });
    return it('preserves running services', function() {
      return testCommands.run(['-a', 'backend-addon', "application." + ENV]).then(function() {
        return testCommands.run(['-a', 'backend-addon', "application." + ENV]);
      }).then(function(arg) {
        var reporter, stdout;
        stdout = arg.stdout, reporter = arg.reporter;
        expect(JSON.parse(stdout)).toEqual(APPLICATION_SUCCESS);
        return expect(reporter.services).toEqual({
          'config': ['Checking', 'Starting'],
          'database': ['Checking'],
          'backend': ['Checking'],
          'application': ['Checking', 'Creating', 'Starting']
        });
      });
    });
  });
  describe('commands', function() {
    it('allows source, entrypoint, and new command', function() {
      return testCommands.run(['--entrypoint', 'cat', '-s', 'acceptance/fixtures/src', "application." + ENV, '/src/code.txt']).then(function(arg) {
        var reporter, stderr, stdout;
        stdout = arg.stdout, stderr = arg.stderr, reporter = arg.reporter;
        return expect(stdout).toEqual("println 'Hello World!'\n");
      });
    });
    return it('sets env variables, pipes stdin through correctly', function() {
      return testCommands.run(['-e', 'COUNT_CMD=/usr/bin/wc', "application." + ENV, '/bin/sh', '-c', '$COUNT_CMD'], {
        stdin: 'kittens puppies'
      }).then(function(arg) {
        var reporter, stdout;
        stdout = arg.stdout, reporter = arg.reporter;
        return expect(stdout).toEqual('      0       2      15\n');
      });
    });
  });
  describe('links', function() {
    it('creates removed linked-to services', function() {
      return testCommands.exec("docker rm -f backend." + ENV).then(function() {
        return testCommands.run(['-a', 'backend-addon', "application." + ENV]);
      }).then(function(arg) {
        var reporter, stdout;
        stdout = arg.stdout, reporter = arg.reporter;
        expect(JSON.parse(stdout)).toEqual(APPLICATION_SUCCESS);
        return expect(reporter.services).toEqual({
          'config': ['Checking', 'Starting'],
          'database': ['Checking', 'Starting'],
          'backend': ['Checking', 'Creating', 'Starting'],
          'application': ['Checking', 'Creating', 'Starting']
        });
      });
    });
    it('recreates services with removed linked-to services', function() {
      return testCommands.exec("docker rm -f database." + ENV).then(function() {
        return testCommands.run(['-a', 'backend-addon', "application." + ENV]);
      }).then(function(arg) {
        var reporter, stdout;
        stdout = arg.stdout, reporter = arg.reporter;
        expect(JSON.parse(stdout)).toEqual(APPLICATION_SUCCESS);
        return expect(reporter.services).toEqual({
          'config': ['Checking', 'Starting'],
          'database': ['Checking', 'Creating', 'Starting'],
          'backend': ['Checking', 'Removing', 'Creating', 'Starting'],
          'application': ['Checking', 'Creating', 'Starting']
        });
      });
    });
    return it('uses existing backend container', function() {
      return testCommands.run(['-s', 'acceptance/fixtures/public', '--rsync', '--detach', "backend." + ENV]).then(function(arg) {
        var reporter, stdout;
        stdout = arg.stdout, reporter = arg.reporter;
        expect(reporter.services).toEqual({
          'backend (rsync)': ['Checking', 'Creating', 'Starting', 'Syncing'],
          'config': ['Checking', 'Starting'],
          'database': ['Checking', 'Starting'],
          'backend': ['Checking', 'Removing', 'Creating', 'Starting']
        });
        return testCommands.run(['-a', 'backend-addon', "application." + ENV]);
      }).then(function(arg) {
        var reporter, stdout;
        stdout = arg.stdout, reporter = arg.reporter;
        expect(JSON.parse(stdout)).toEqual(_.merge({}, APPLICATION_SUCCESS, {
          index: 'Hello, Source!\n'
        }));
        return expect(reporter.services).toEqual({
          'config': ['Checking', 'Starting'],
          'database': ['Checking'],
          'backend': ['Checking'],
          'application': ['Checking', 'Creating', 'Starting']
        });
      })["finally"](function() {
        testCommands.exec('docker rm -vf backend.galley-integration-rsync');
        return testCommands.run(['--detach', "backend." + ENV]);
      });
    });
  });
  return describe('volumes', function() {
    return it('recreates after volume is deleted', function() {
      return testCommands.exec("docker rm -f config." + ENV).then(function() {
        return testCommands.run(['-a', 'backend-addon', "application." + ENV]);
      }).then(function(arg) {
        var reporter, stdout;
        stdout = arg.stdout, reporter = arg.reporter;
        expect(JSON.parse(stdout)).toEqual(APPLICATION_SUCCESS);
        return expect(reporter.services).toEqual({
          'config': ['Checking', 'Creating', 'Starting'],
          'database': ['Checking', 'Starting'],
          'backend': ['Checking', 'Removing', 'Creating', 'Starting'],
          'application': ['Checking', 'Creating', 'Starting']
        });
      });
    });
  });
});
