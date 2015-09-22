var ConsoleReporter, Docker, DockerConfig, DockerUtils, PromiseUtils, RSVP, ServiceHelpers, _, chalk, findContainerName, help, lookupServiceConfig, maybeRemoveContainer, minimist, removeImage,
  slice = [].slice;

_ = require('lodash');

chalk = require('chalk');

minimist = require('minimist');

ConsoleReporter = require('../lib/console_reporter');

Docker = require('dockerode');

DockerConfig = require('../lib/docker_config');

DockerUtils = require('../lib/docker_utils');

PromiseUtils = require('../lib/promise_utils');

ServiceHelpers = require('../lib/service_helpers');

RSVP = require('rsvp');

help = require('./help');

findContainerName = function(info) {
  var i, len, name, ref;
  ref = info.Names;
  for (i = 0, len = ref.length; i < len; i++) {
    name = ref[i];
    if ((name.match(/\//g) || []).length === 1) {
      return name.substr(1);
    }
  }
};

lookupServiceConfig = function(service, env, options, configCache) {
  if (configCache[env] == null) {
    configCache[env] = ServiceHelpers.processConfig(options.config, env, []).servicesConfig;
  }
  return configCache[env][service];
};

maybeRemoveContainer = function(docker, info, options, configCache) {
  var anonymousContainer, config, containerName, env, envParts, ref, removePromise, service, statefulContainer;
  containerName = findContainerName(info);
  ref = containerName.split('.'), service = ref[0], envParts = 2 <= ref.length ? slice.call(ref, 1) : [];
  env = envParts.join('.');
  if (env.length && (config = lookupServiceConfig(service, env, options, configCache))) {
    anonymousContainer = false;
    statefulContainer = config.stateful;
  } else {
    anonymousContainer = true;
    statefulContainer = false;
  }
  if (anonymousContainer && !options.unprotectAnonymous) {
    return RSVP.resolve();
  }
  options.reporter.startService(containerName);
  removePromise = !(statefulContainer && !options.unprotectStateful) ? (options.reporter.startTask('Removing'), DockerUtils.removeContainer(docker.getContainer(info.Id), {
    v: true
  }).then(function() {
    return options.reporter.succeedTask();
  })) : (options.reporter.completeTask('Preserving stateful service'), RSVP.resolve({}));
  return removePromise["finally"](function() {
    return options.reporter.finish();
  });
};

removeImage = function(docker, info) {
  return DockerUtils.removeImage(docker.getImage(info.Id))["catch"](function(err) {
    if (err.statusCode === 409) {

    } else {
      throw err;
    }
  });
};

module.exports = function(args, commandOptions, done) {
  var argv, configCache, docker, options;
  argv = minimist(args, {
    boolean: ['help', 'unprotectAnonymous', 'unprotectStateful']
  });
  if (argv._.length !== 0 || argv.help) {
    return help(args, commandOptions, done);
  }
  docker = new Docker(DockerConfig.connectionConfig());
  options = {
    unprotectStateful: argv.unprotectStateful,
    unprotectAnonymous: argv.unprotectAnonymous,
    stderr: commandOptions.stderr || process.stderr,
    reporter: commandOptions.reporter || new ConsoleReporter(process.stderr),
    config: commandOptions.config
  };
  configCache = {};
  return DockerUtils.listContainers(docker, {
    filters: '{"status": ["exited"]}'
  }).then(function(arg) {
    var infos;
    infos = arg.infos;
    options.reporter.message('Removing stopped containers…');
    return PromiseUtils.promiseEach(infos, function(info) {
      return maybeRemoveContainer(docker, info, options, configCache);
    });
  }).then(function() {
    return DockerUtils.listImages(docker, {
      filters: '{"dangling": ["true"]}'
    });
  }).then(function(arg) {
    var count, infos, progressLine, updateProgress;
    infos = arg.infos;
    if (commandOptions.preserveUntagged) {
      return;
    }
    options.reporter.message();
    count = 0;
    progressLine = options.reporter.startProgress('Deleting dangling images…');
    updateProgress = function() {
      return progressLine.set(count + " / " + infos.length);
    };
    updateProgress();
    return PromiseUtils.promiseEach(infos, function(info) {
      return removeImage(docker, info).then(function() {
        count++;
        return updateProgress();
      });
    }).then(function() {
      progressLine.clear();
      options.reporter.succeedTask();
      return options.reporter.finish();
    });
  }).then(function() {
    return done();
  })["catch"](function(err) {
    var message;
    if ((err != null) && err !== '' && typeof err === 'string' || (err.json != null)) {
      message = ((err != null ? err.json : void 0) || (typeof err === 'string' ? err : void 0) || (err != null ? err.message : void 0) || 'Unknown error').trim();
      message = message.replace(/^Error: /, '');
      options.reporter.error(chalk.bold('Error:') + ' ' + message);
    }
    options.reporter.finish();
    if (err != null ? err.stack : void 0) {
      return options.stderr.write(err != null ? err.stack : void 0);
    }
  });
};
