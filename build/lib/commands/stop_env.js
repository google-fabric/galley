var ConsoleReporter, Docker, RSVP, _, help, stopContainer;

_ = require('lodash');

ConsoleReporter = require('../lib/console_reporter');

Docker = require('dockerode');

RSVP = require('rsvp');

help = require('./help');

stopContainer = function(name, container, reporter) {
  return new RSVP.Promise(function(resolve, reject) {
    reporter.startService(name).startTask('Stopping');
    return container.stop(function(err, data) {
      if (err && err.statusCode !== 304) {
        reporter.error(err.json || ("Error " + err.statusCode + " stopping container"));
      } else {
        reporter.succeedTask().finish();
      }
      return resolve();
    });
  });
};

module.exports = function(args, options, done) {
  var docker, env, reporter;
  docker = new Docker();
  if (args.length !== 1) {
    return help(args, options, done);
  }
  env = args[0];
  reporter = options.reporter || new ConsoleReporter(process.stderr);
  return docker.listContainers(function(err, containerInfos) {
    var containerInfo, found, i, id, j, len, len1, name, promise, ref;
    if (err) {
      throw err;
    }
    promise = RSVP.resolve();
    found = false;
    for (i = 0, len = containerInfos.length; i < len; i++) {
      containerInfo = containerInfos[i];
      id = containerInfo.Id;
      ref = containerInfo.Names;
      for (j = 0, len1 = ref.length; j < len1; j++) {
        name = ref[j];
        if (name.match(new RegExp("\." + env + "$"))) {
          found = true;
          (function(id, name) {
            return promise = promise.then(function() {
              return stopContainer(name, docker.getContainer(id), reporter);
            });
          })(id, name);
          break;
        }
      }
    }
    if (found) {
      return promise.then(done);
    } else {
      reporter.message('No containers found to stop');
      return typeof done === "function" ? done() : void 0;
    }
  });
};
