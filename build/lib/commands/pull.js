var Docker, DockerConfig, DockerUtils, ProgressLine, RSVP, ServiceHelpers, _, chalk, help, minimist, parseArgs, pullService,
  slice = [].slice;

_ = require('lodash');

chalk = require('chalk');

Docker = require('dockerode');

RSVP = require('rsvp');

minimist = require('minimist');

help = require('./help');

ProgressLine = require('../lib/progress_line');

DockerConfig = require('../lib/docker_config');

DockerUtils = require('../lib/docker_utils');

ServiceHelpers = require('../lib/service_helpers');

parseArgs = function(args) {
  var argv, env, envArr, options, ref, service;
  argv = minimist(args, {
    alias: {
      'add': 'a'
    }
  });
  ref = (argv._[0] || '').split('.'), service = ref[0], envArr = 2 <= ref.length ? slice.call(ref, 1) : [];
  env = envArr.join('.');
  options = {};
  _.merge(options, _.pick(argv, ['add']));
  options.add = ServiceHelpers.normalizeMultiArgs(options.add);
  return {
    service: service,
    env: env,
    options: options
  };
};

pullService = function(docker, servicesConfig, service, env) {
  var prereqPromise, prereqsArray;
  prereqsArray = ServiceHelpers.generatePrereqServices(service, servicesConfig);
  prereqPromise = RSVP.resolve();
  _.forEach(prereqsArray, function(prereq) {
    var imageName, progressLine;
    imageName = servicesConfig[prereq].image;
    progressLine = new ProgressLine(process.stderr, chalk.gray);
    return prereqPromise = prereqPromise.then(function() {
      process.stderr.write(chalk.blue(prereq + ':'));
      process.stderr.write(chalk.gray(' Pulling… '));
      return DockerUtils.downloadImage(docker, imageName, DockerConfig.authConfig, progressLine.set.bind(progressLine));
    })["finally"](function() {
      return progressLine.clear();
    }).then(function() {
      return process.stderr.write(chalk.green(' done!'));
    })["catch"](function(err) {
      if ((err != null ? err.statusCode : void 0) === 404) {
        throw "Image " + imageName + " not found in registry";
      } else {
        throw err;
      }
    })["catch"](function(err) {
      if ((err != null) && err !== '' && typeof err === 'string' || (err.json != null)) {
        process.stderr.write(chalk.red(' ' + chalk.bold('Error:') + ' ' + ((err != null ? err.json : void 0) || err).trim()));
        throw '';
      } else {
        throw err;
      }
    })["finally"](function() {
      return process.stderr.write('\n');
    });
  });
  return prereqPromise;
};

module.exports = function(args, commandOptions, done) {
  var docker, env, options, ref, service, servicesConfig;
  ref = parseArgs(args), service = ref.service, env = ref.env, options = ref.options;
  if (!((service != null) && !_.isEmpty(service))) {
    return help(args, commandOptions, done);
  }
  servicesConfig = ServiceHelpers.processConfig(commandOptions.config, env, options.add).servicesConfig;
  docker = new Docker();
  return pullService(docker, servicesConfig, service, env).then(function() {
    return typeof done === "function" ? done() : void 0;
  })["catch"](function(e) {
    console.error((e != null ? e.stack : void 0) || 'Aborting. ');
    return process.exit(-1);
  });
};
