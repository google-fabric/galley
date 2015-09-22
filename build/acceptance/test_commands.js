var GALLEYFILE, RSVP, TestReporter, child_process, cleanup, cleanupCommand, exec, run, runCommand, stopEnv, stopEnvCommand, stream, streamBuffers;

child_process = require('child_process');

RSVP = require('rsvp');

stream = require('stream');

streamBuffers = require('stream-buffers');

TestReporter = require('../spec/util/test_reporter');

cleanupCommand = require('../lib/commands/cleanup');

runCommand = require('../lib/commands/run');

stopEnvCommand = require('../lib/commands/stop_env');

GALLEYFILE = require('./Galleyfile');

exec = function(cmd) {
  return new RSVP.Promise(function(resolve, reject) {
    return child_process.exec(cmd, function(err, stdout, stderr) {
      if (err) {
        return reject(err);
      } else {
        return resolve({
          stdout: stdout.toString(),
          stderr: stderr.toString()
        });
      }
    });
  });
};

run = function(args, runOpts) {
  if (runOpts == null) {
    runOpts = {};
  }
  return new RSVP.Promise(function(resolve, reject) {
    var options, stdin;
    stdin = new stream.Readable;
    stdin.push(runOpts.stdin || '');
    stdin.push(null);
    options = {
      config: GALLEYFILE,
      stdin: stdin,
      stdout: new streamBuffers.WritableStreamBuffer({
        frequency: 0
      }),
      stderr: new streamBuffers.WritableStreamBuffer({
        frequency: 0
      }),
      reporter: new TestReporter
    };
    return runCommand(args, options, function(statusCode) {
      if (statusCode == null) {
        statusCode = 0;
      }
      if (statusCode !== 0) {
        return reject(new Error(options.reporter.lastError || options.stderr.getContentsAsString("utf8")));
      } else {
        return resolve({
          reporter: options.reporter,
          statusCode: statusCode,
          stderr: options.stderr.getContentsAsString("utf8"),
          stdout: options.stdout.getContentsAsString("utf8")
        });
      }
    });
  });
};

cleanup = function() {
  return new RSVP.Promise(function(resolve, reject) {
    var options;
    options = {
      config: GALLEYFILE,
      reporter: new TestReporter,
      preserveUntagged: true
    };
    return cleanupCommand([], options, function() {
      return resolve({
        reporter: options.reporter
      });
    });
  });
};

stopEnv = function(env) {
  return new RSVP.Promise(function(resolve, reject) {
    return stopEnvCommand([env], {
      reporter: new TestReporter
    }, resolve);
  });
};

module.exports = {
  exec: exec,
  run: run,
  cleanup: cleanup,
  stopEnv: stopEnv
};
