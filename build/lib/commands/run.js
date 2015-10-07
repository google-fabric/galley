var ConsoleReporter, Docker, DockerArgs, DockerConfig, DockerUtils, LocalhostForwarder, OverlayOutputStream, RECREATE_OPTIONS, RSVP, Rsyncer, ServiceHelpers, StdinCommandInterceptor, _, areVolumesOutOfDate, chalk, containerIsCurrentlyGalleyManaged, containerNeedsRecreate, downloadServiceImage, ensureContainerConfigured, ensureContainerRunning, ensureImageAvailable, finalizeContainer, go, help, isContainerImageStale, isLinkMissing, makeCreateOpts, makeRsyncerWatchCallback, maybeAttachStream, maybeInspectContainer, maybePipeStdStreams, maybeRemoveContainer, maybeRepairSourceOwnership, minimist, parseArgs, path, pipeStreamsLoop, prepareServiceSource, printDetachedMessage, running, spin, startService, startServices, updateCompletedServicesMap, util,
  slice = [].slice,
  indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

_ = require('lodash');

chalk = require('chalk');

Docker = require('dockerode');

RSVP = require('rsvp');

util = require('util');

path = require('path');

minimist = require('minimist');

spin = require('term-spinner');

running = require('is-running');

help = require('./help');

ConsoleReporter = require('../lib/console_reporter');

DockerArgs = require('../lib/docker_args');

DockerConfig = require('../lib/docker_config');

DockerUtils = require('../lib/docker_utils');

LocalhostForwarder = require('../lib/localhost_forwarder');

OverlayOutputStream = require('../lib/overlay_output_stream');

Rsyncer = require('../lib/rsyncer');

ServiceHelpers = require('../lib/service_helpers');

StdinCommandInterceptor = require('../lib/stdin_command_interceptor');

RECREATE_OPTIONS = ['all', 'stale', 'missing-link'];

makeCreateOpts = function(imageInfo, serviceConfig, servicesMap, options) {
  var containerNameMap, createOpts, defaultWorkingDir, exposedPorts, portBindings, ref, ref1, volumesFrom;
  containerNameMap = _.mapValues(servicesMap, 'containerName');
  volumesFrom = DockerArgs.formatVolumesFrom(serviceConfig.volumesFrom, containerNameMap).concat(serviceConfig.containerVolumesFrom || []);
  createOpts = {
    'name': serviceConfig.containerName,
    'Image': imageInfo.Id,
    'Env': DockerArgs.formatEnvVariables(serviceConfig.env),
    'Labels': {
      'io.fabric.galley.primary': 'false'
    },
    'User': serviceConfig.user,
    'Volumes': DockerArgs.formatVolumes(serviceConfig.volumes),
    'HostConfig': {
      'ExtraHosts': [serviceConfig.name + ":127.0.0.1"],
      'Links': DockerArgs.formatLinks(serviceConfig.links, containerNameMap),
      'Binds': serviceConfig.binds,
      'VolumesFrom': volumesFrom
    }
  };
  if (serviceConfig.publishPorts) {
    ref = DockerArgs.formatPortBindings(serviceConfig.ports), portBindings = ref.portBindings, exposedPorts = ref.exposedPorts;
    createOpts['HostConfig']['PortBindings'] = portBindings;
    if (exposedPorts !== {}) {
      createOpts['ExposedPorts'] = exposedPorts;
      createOpts['HostConfig']['PublishAllPorts'] = true;
    }
  }
  if (serviceConfig.primary != null) {
    createOpts['Labels']['io.fabric.galley.primary'] = 'true';
    createOpts['Labels']['io.fabric.galley.pid'] = "" + process.pid;
  }
  if (serviceConfig.command != null) {
    createOpts['Cmd'] = serviceConfig.command;
  }
  if (serviceConfig.restart) {
    createOpts['HostConfig']['RestartPolicy'] = {
      'Name': 'always'
    };
  }
  if (serviceConfig.entrypoint != null) {
    createOpts['Entrypoint'] = serviceConfig.entrypoint === '' ? [] : serviceConfig.entrypoint;
  }
  if (serviceConfig.workdir != null) {
    defaultWorkingDir = imageInfo.Config.WorkingDir || '/';
    createOpts['WorkingDir'] = path.resolve(defaultWorkingDir, serviceConfig.workdir);
  }
  if (serviceConfig.attach) {
    _.merge(createOpts, {
      'Tty': (ref1 = options.stdin) != null ? ref1.isTTY : void 0,
      'OpenStdin': true,
      'StdinOnce': true
    });
  }
  return createOpts;
};

downloadServiceImage = function(docker, imageName, options) {
  var progressLine;
  options.reporter.startTask('Downloading');
  progressLine = options.reporter.startProgress();
  return DockerUtils.downloadImage(docker, imageName, DockerConfig.authConfig, progressLine.set.bind(progressLine))["finally"](function() {
    return progressLine.clear();
  }).then(function() {
    return options.reporter.succeedTask();
  });
};

ensureImageAvailable = function(docker, imageName, options) {
  var image;
  image = docker.getImage(imageName);
  return DockerUtils.inspectImage(image)["catch"](function(err) {
    if ((err != null ? err.statusCode : void 0) !== 404) {
      throw err;
    }
    return downloadServiceImage(docker, imageName, options).then(function() {
      return DockerUtils.inspectImage(image);
    });
  }).then(function(arg) {
    var image, info;
    image = arg.image, info = arg.info;
    return {
      image: image,
      info: info
    };
  });
};

maybeInspectContainer = function(docker, name) {
  if (!name) {
    return RSVP.resolve({
      container: null,
      info: null
    });
  } else {
    return DockerUtils.inspectContainer(docker.getContainer(name)).then(function(arg) {
      var container, info;
      container = arg.container, info = arg.info;
      return {
        container: container,
        info: info
      };
    })["catch"](function(err) {
      if ((err != null ? err.statusCode : void 0) === 404) {
        return {
          container: null,
          info: null
        };
      } else {
        throw err;
      }
    });
  }
};

isLinkMissing = function(containerInfo, createOpts) {
  var currentLinks, ref, requestedLinks;
  currentLinks = _.map((containerInfo != null ? (ref = containerInfo.HostConfig) != null ? ref.Links : void 0 : void 0) || [], function(link) {
    var dest, ref1, source;
    ref1 = link.split(':'), source = ref1[0], dest = ref1[1];
    return source + ":" + (dest.split('/').pop());
  });
  requestedLinks = createOpts.HostConfig.Links.concat();
  currentLinks.sort();
  requestedLinks.sort();
  return !_.isEqual(currentLinks, requestedLinks);
};

areVolumesOutOfDate = function(containerInfo, serviceConfig, completedServicesMap) {
  var expectedVolumes, mountPoint, volumePath, volumePathsArray;
  volumePathsArray = _.map(serviceConfig.volumesFrom || [], function(service) {
    return completedServicesMap[service].volumePaths;
  });
  expectedVolumes = _.merge.apply(_, [{}].concat(volumePathsArray));
  for (mountPoint in expectedVolumes) {
    volumePath = expectedVolumes[mountPoint];
    if (containerInfo.Volumes[mountPoint] !== volumePath) {
      return true;
    }
  }
  return false;
};

isContainerImageStale = function(containerInfo, imageInfo) {
  return imageInfo.Id !== containerInfo.Config.Image;
};

containerNeedsRecreate = function(containerInfo, imageInfo, serviceConfig, createOpts, options, servicesMap) {
  if (serviceConfig.forceRecreate) {
    return true;
  } else if (serviceConfig.stateful && !options.unprotectStateful) {
    return false;
  } else if (isLinkMissing(containerInfo, createOpts)) {
    return true;
  } else if (areVolumesOutOfDate(containerInfo, serviceConfig, servicesMap)) {
    return true;
  } else {
    switch (options.recreate) {
      case 'all':
        return true;
      case 'stale':
        return isContainerImageStale(containerInfo, imageInfo);
      default:
        return false;
    }
  }
};

containerIsCurrentlyGalleyManaged = function(containerInfo) {
  var pid;
  if ((containerInfo.Config.Labels != null) && containerInfo.Config.Labels['io.fabric.galley.primary'] === 'true') {
    pid = parseInt(containerInfo.Config.Labels['io.fabric.galley.pid']);
    if (pid === !process.pid) {
      return running(pid);
    }
  }
};

maybeRemoveContainer = function(container, containerInfo, imageInfo, serviceConfig, createOpts, options, servicesMap) {
  return new RSVP.Promise(function(resolve, reject) {
    var promise;
    if (container == null) {
      options.reporter.completeTask('not found.');
      return resolve({
        container: null
      });
    } else if (containerNeedsRecreate(containerInfo, imageInfo, serviceConfig, createOpts, options, servicesMap)) {
      if (containerIsCurrentlyGalleyManaged(containerInfo)) {
        reject("Cannot be recreated, container is managed by another Galley process.\n Check that all images are up to date, and that addons requested here match those in the managed Galley container.");
      }
      options.reporter.completeTask('needs recreate').startTask('Removing');
      promise = DockerUtils.removeContainer(container, {
        force: true,
        v: true
      }).then(function() {
        options.reporter.succeedTask();
        return {
          container: null
        };
      });
      return resolve(promise);
    } else {
      options.reporter.succeedTask('ok');
      return resolve({
        container: container
      });
    }
  });
};

ensureContainerConfigured = function(docker, imageInfo, service, serviceConfig, options, servicesMap) {
  var createOpts;
  options.reporter.startTask('Checking');
  createOpts = makeCreateOpts(imageInfo, serviceConfig, servicesMap, options);
  return maybeInspectContainer(docker, serviceConfig.containerName).then(function(arg) {
    var container, containerInfo;
    container = arg.container, containerInfo = arg.info;
    return maybeRemoveContainer(container, containerInfo, imageInfo, serviceConfig, createOpts, options, servicesMap).then(function(arg1) {
      var container;
      container = arg1.container;
      return {
        container: container,
        info: containerInfo
      };
    });
  }).then(function(arg) {
    var container, info;
    container = arg.container, info = arg.info;
    if (container != null) {
      servicesMap[service].freshlyCreated = false;
      return {
        container: container,
        info: info
      };
    }
    options.reporter.startTask('Creating');
    return DockerUtils.createContainer(docker, createOpts).then(function(arg1) {
      var container;
      container = arg1.container;
      servicesMap[service].freshlyCreated = true;
      return DockerUtils.inspectContainer(container);
    }).then(function(arg1) {
      var container, info;
      container = arg1.container, info = arg1.info;
      options.reporter.succeedTask();
      return {
        container: container,
        info: info
      };
    });
  });
};

ensureContainerRunning = function(container, info, service, serviceConfig, options) {
  var actionPromise;
  actionPromise = null;
  if (!info.State.Running) {
    options.reporter.startTask('Starting');
    actionPromise = DockerUtils.startContainer(container);
  } else if (info.State.Paused) {
    options.reporter.startTask('Unpausing');
    actionPromise = DockerUtils.unpauseContainer(container);
  } else {
    return RSVP.resolve({
      container: container,
      info: info
    });
  }
  return actionPromise.then(function() {
    return DockerUtils.inspectContainer(container);
  }).then(function(arg) {
    var container, info;
    container = arg.container, info = arg.info;
    options.reporter.succeedTask();
    return {
      container: container,
      info: info
    };
  });
};

maybeAttachStream = function(container, serviceConfig) {
  return new RSVP.Promise(function(resolve, reject) {
    var promise;
    if (serviceConfig != null ? serviceConfig.attach : void 0) {
      promise = DockerUtils.attachContainer(container, {
        stream: true,
        stdin: false,
        stdout: true,
        stderr: true
      }).then(function(arg) {
        var container, stream;
        container = arg.container, stream = arg.stream;
        return {
          container: container,
          stream: stream
        };
      });
      return resolve(promise);
    } else {
      return resolve({
        container: container,
        stream: null
      });
    }
  });
};

maybePipeStdStreams = function(container, outputStream, options) {
  if (outputStream === null) {
    return RSVP.resolve({
      container: container,
      resolution: 'unattached'
    });
  }
  return DockerUtils.attachContainer(container, {
    stream: true,
    stdin: true,
    stdout: false,
    stderr: false
  }).then(function(arg) {
    var container, inputStream, outputStreamEndHandler, resizeHandler, stdinCommandInterceptorHandler;
    container = arg.container, inputStream = arg.stream;
    options.stdinCommandInterceptor.start(inputStream);
    resizeHandler = function() {
      return DockerUtils.resizeContainer(container, options.stdout);
    };
    stdinCommandInterceptorHandler = null;
    outputStreamEndHandler = null;
    return new RSVP.Promise(function(resolve, reject) {
      stdinCommandInterceptorHandler = function(arg1) {
        var command;
        command = arg1.command;
        options.stdinCommandInterceptor.stop();
        outputStream.destroy();
        return resolve({
          container: container,
          resolution: command
        });
      };
      outputStreamEndHandler = function() {
        options.stdinCommandInterceptor.stop();
        return resolve({
          container: container,
          resolution: 'end'
        });
      };
      options.stdinCommandInterceptor.on('command', stdinCommandInterceptorHandler);
      outputStream.on('end', outputStreamEndHandler);
      if (options.stdout.isTTY) {
        outputStream.setEncoding('utf8');
        outputStream.pipe(options.stdout, {
          end: false
        });
        resizeHandler();
        return options.stdout.on('resize', resizeHandler);
      } else {
        outputStream.on('end', function() {
          var error1, error2;
          try {
            options.stdout.end();
          } catch (error1) {

          }
          try {
            return options.stderr.end();
          } catch (error2) {

          }
        });
        return container.modem.demuxStream(outputStream, options.stdout, options.stderr);
      }
    })["finally"](function() {
      options.stdout.removeListener('resize', resizeHandler);
      options.stdinCommandInterceptor.removeListener('command', stdinCommandInterceptorHandler);
      return outputStream.removeListener('end', outputStreamEndHandler);
    });
  });
};

updateCompletedServicesMap = function(service, serviceConfig, containerInfo, completedServicesMap) {
  var exportedMounts, exportedPaths;
  completedServicesMap[service].containerName = containerInfo.Name;
  exportedMounts = _.keys(containerInfo.Config.Volumes || {});
  exportedPaths = _.pick(containerInfo.Volumes || {}, exportedMounts);
  return completedServicesMap[service].volumePaths = exportedPaths;
};

startService = function(docker, serviceConfig, service, options, completedServicesMap) {
  options.reporter.startService(service);
  if (completedServicesMap[service]) {
    throw "Service already completed: " + service;
  }
  completedServicesMap[service] = {
    containerName: null,
    freshlyCreated: null,
    volumePaths: null
  };
  return ensureImageAvailable(docker, serviceConfig.image, options).then(function(arg) {
    var image, imageInfo;
    image = arg.image, imageInfo = arg.info;
    return ensureContainerConfigured(docker, imageInfo, service, serviceConfig, options, completedServicesMap);
  }).then(function(arg) {
    var container, containerInfo;
    container = arg.container, containerInfo = arg.info;
    return maybeAttachStream(container, serviceConfig).then(function(arg1) {
      var container, stream;
      container = arg1.container, stream = arg1.stream;
      return {
        container: container,
        stream: stream,
        info: containerInfo
      };
    });
  }).then(function(arg) {
    var container, containerInfo, stream;
    container = arg.container, stream = arg.stream, containerInfo = arg.info;
    return ensureContainerRunning(container, containerInfo, service, serviceConfig, options).then(function(arg1) {
      var container, containerInfo, forwarderReceipt, maybeForwardPromise;
      container = arg1.container, containerInfo = arg1.info;
      if (!options.leaveReporterOpen) {
        options.reporter.finish();
      }
      updateCompletedServicesMap(service, serviceConfig, containerInfo, completedServicesMap);
      forwarderReceipt = null;
      maybeForwardPromise = serviceConfig.localhost ? DockerUtils.inspectContainer(container).then(function(arg2) {
        var info, outs, ports, ref, source;
        info = arg2.info;
        ports = [];
        ref = containerInfo.NetworkSettings.Ports || {};
        for (source in ref) {
          outs = ref[source];
          ports.push(parseInt(outs[0].HostPort));
        }
        if (ports.length) {
          return forwarderReceipt = options.localhostForwarder.forward(ports);
        }
      }) : RSVP.resolve();
      return maybeForwardPromise.then(function() {
        return pipeStreamsLoop(container, stream, serviceConfig, options);
      })["finally"](function() {
        if (forwarderReceipt) {
          return forwarderReceipt.stop();
        }
      });
    }).then(function(arg1) {
      var container, resolution;
      container = arg1.container, resolution = arg1.resolution;
      return {
        container: container,
        resolution: resolution
      };
    });
  });
};

pipeStreamsLoop = function(container, stream, serviceConfig, options) {
  return maybePipeStdStreams(container, stream, options).then(function(arg) {
    var container, resolution;
    container = arg.container, resolution = arg.resolution;
    if (resolution === 'end') {
      return DockerUtils.inspectContainer(container).then(function(arg1) {
        var container, info;
        container = arg1.container, info = arg1.info;
        if (info.State.Running || info.State.Restarting) {
          return maybeAttachStream(container, serviceConfig).then(function(arg2) {
            var container, stream;
            container = arg2.container, stream = arg2.stream;
            return pipeStreamsLoop(container, stream, serviceConfig, options);
          });
        } else {
          return {
            container: container,
            resolution: resolution
          };
        }
      });
    } else {
      return {
        container: container,
        resolution: resolution
      };
    }
  });
};

maybeRepairSourceOwnership = function(docker, config, service, options) {
  var createOpts, repairScript, serviceConfig;
  serviceConfig = config[service] || {};
  if (!(options.repairSourceOwnership && (serviceConfig.source != null))) {
    return RSVP.resolve(false);
  }
  repairScript = "chown -R $(stat --format '%u:%g' .) .";
  createOpts = {
    'Image': serviceConfig.image,
    'Entrypoint': [],
    'WorkingDir': serviceConfig.source,
    'Cmd': ['bash', '-c', repairScript],
    'HostConfig': {
      'Binds': serviceConfig.binds
    }
  };
  options.reporter.startTask('Repairing source ownership');
  return DockerUtils.createContainer(docker, createOpts).then(function(arg) {
    var container;
    container = arg.container;
    return DockerUtils.startContainer(container);
  }).then(function(arg) {
    var container;
    container = arg.container;
    return DockerUtils.waitContainer(container);
  }).then(function(arg) {
    var container, result;
    container = arg.container, result = arg.result;
    return DockerUtils.removeContainer(container, {
      v: true
    }).then(function() {
      if (result.StatusCode === 0) {
        return options.reporter.succeedTask().finish();
      } else {
        return options.reporter.error("Failed with exit code " + result.StatusCode);
      }
    });
  }).then(function() {
    return true;
  });
};

printDetachedMessage = function(container, options) {
  return DockerUtils.inspectContainer(container).then(function(arg) {
    var container, info, name;
    container = arg.container, info = arg.info;
    name = info.Name.replace(/^\//, '');
    options.reporter.message('');
    options.reporter.message('');
    options.reporter.message(chalk.gray('Container detached: ') + chalk.bold(name));
    options.reporter.message(chalk.gray('Reattach with: ') + ("docker attach " + name));
    return options.reporter.message(chalk.gray('Remove with: ') + ("docker rm -fv " + name));
  });
};

finalizeContainer = function(container, options) {
  return DockerUtils.inspectContainer(container).then(function(arg) {
    var container, info, statusCode;
    container = arg.container, info = arg.info;
    statusCode = info.State.ExitCode;
    if ((statusCode != null) && statusCode !== 0) {
      options.reporter.error((info.Config.Cmd.join(' ')) + " failed with exit code " + statusCode);
    }
    return DockerUtils.removeContainer(container).then(function() {
      return {
        container: container,
        statusCode: statusCode
      };
    });
  });
};

makeRsyncerWatchCallback = function(options) {
  var lastTime, spinner;
  lastTime = null;
  spinner = spin["new"]();
  return function(status, source, files, error) {
    var base, base1, base2, desc;
    switch (status) {
      case 'watching':
        return typeof (base = options.stdout).setOverlayStatus === "function" ? base.setOverlayStatus("Watching " + (path.basename(source)) + "…") : void 0;
      case 'changed':
        if (lastTime === null) {
          return lastTime = Date.now();
        }
        break;
      case 'syncing':
        spinner.next();
        return typeof (base1 = options.stdout).setOverlayStatus === "function" ? base1.setOverlayStatus(spinner.current + " Synching " + (path.basename(source)) + "…") : void 0;
      case 'synched':
        files = _.uniq(files);
        if (files.length === 1) {
          desc = path.basename(files[0]);
        } else {
          desc = files.length + " files";
        }
        if (typeof (base2 = options.stdout).flashOverlayMessage === "function") {
          base2.flashOverlayMessage("Synched " + desc + " (" + (Date.now() - lastTime) + "ms)");
        }
        return lastTime = null;
      case 'error':
        return options.reporter.error(error);
    }
  };
};

prepareServiceSource = function(docker, globalConfig, config, service, env, options) {
  var primaryServiceConfig, rsyncConfig, rsyncPort, rsyncServiceConfig, suffix;
  primaryServiceConfig = config[service];
  if (!options.source) {
    return RSVP.resolve({});
  }
  if (!options.rsync) {
    primaryServiceConfig.binds.push(options.source + ":" + primaryServiceConfig.source);
    return RSVP.resolve({});
  }
  rsyncConfig = globalConfig.rsync;
  if (!((rsyncConfig != null ? rsyncConfig.image : void 0) && (rsyncConfig != null ? rsyncConfig.module : void 0))) {
    return RSVP.reject('--rsync requires CONFIG.rsync image and module definitions');
  }
  rsyncPort = rsyncConfig.port || 873;
  suffix = rsyncConfig.suffix || 'rsync';
  rsyncServiceConfig = _.merge({}, ServiceHelpers.DEFAULT_SERVICE_CONFIG, {
    containerName: service + "." + suffix,
    image: rsyncConfig.image,
    ports: ["" + rsyncPort],
    publishPorts: true,
    volumes: [primaryServiceConfig.source]
  });
  options = _.merge({}, options, {
    leaveReporterOpen: true
  });
  return startService(docker, rsyncServiceConfig, service + " (rsync)", options, {}).then(function(arg) {
    var container;
    container = arg.container;
    return DockerUtils.inspectContainer(container);
  }).then(function(arg) {
    var activityCb, container, info, progressLine, rsyncPortInfo, rsyncer;
    container = arg.container, info = arg.info;
    primaryServiceConfig.containerVolumesFrom.push(info.Name);
    options.reporter.startTask('Syncing');
    progressLine = options.reporter.startProgress();
    activityCb = function() {
      return progressLine.set('');
    };
    rsyncPortInfo = info.NetworkSettings.Ports[rsyncPort + "/tcp"];
    rsyncer = new Rsyncer({
      src: options.source,
      dest: primaryServiceConfig.source,
      host: docker.modem.host || 'localhost',
      port: rsyncPortInfo[0].HostPort,
      module: rsyncConfig.module
    });
    return rsyncer.sync(activityCb)["finally"](function() {
      return progressLine.clear();
    }).then(function() {
      options.reporter.succeedTask().finish();
      rsyncer.watch(makeRsyncerWatchCallback(options));
      return {
        rsyncer: rsyncer
      };
    });
  });
};

startServices = function(docker, config, services, options) {
  var completedServicesMap, loopPromise;
  completedServicesMap = {};
  loopPromise = RSVP.resolve();
  _.forEach(services, function(service) {
    return loopPromise = loopPromise.then(function() {
      return startService(docker, config[service], service, options, completedServicesMap);
    });
  });
  return loopPromise.then(function() {
    return completedServicesMap;
  });
};

parseArgs = function(args) {
  var argv, env, envArr, envVar, i, len, name, options, ref, ref1, ref2, service, serviceConfigOverrides, val, volumes;
  argv = minimist(args, {
    stopEarly: true,
    boolean: ['detach', 'localhost', 'publish-all', 'repairSourceOwnership', 'restart', 'rsync', 'unprotectStateful'],
    alias: {
      'add': 'a',
      'detach': 'd',
      'env': 'e',
      'publish-all': 'P',
      'source': 's',
      'user': 'u',
      'volume': 'v',
      'workdir': 'w'
    }
  });
  ref = (argv._[0] || '').split('.'), service = ref[0], envArr = 2 <= ref.length ? slice.call(ref, 1) : [];
  env = envArr.join('.');
  options = {
    recreate: 'stale'
  };
  _.merge(options, _.pick(argv, ['recreate', 'unprotectStateful']));
  if (indexOf.call(args, '--rsync') >= 0) {
    _.merge(options, _.pick(argv, 'rsync'));
  }
  if (indexOf.call(args, '--repairSourceOwnership') >= 0) {
    _.merge(options, _.pick(argv, 'repairSourceOwnership'));
  }
  options.add = ServiceHelpers.normalizeMultiArgs(argv.add);
  if (argv.source) {
    options.source = path.resolve(argv.source);
  }
  if (RECREATE_OPTIONS.indexOf(options.recreate) === -1) {
    throw "Unrecognized recreate option: '" + options.recreate + "'";
  }
  serviceConfigOverrides = {
    attach: true,
    binds: [],
    containerVolumesFrom: [],
    env: {},
    forceRecreate: true,
    publishPorts: true,
    primary: true
  };
  if (argv._.length > 1) {
    _.merge(serviceConfigOverrides, {
      command: argv._.slice(1),
      containerName: '',
      publishPorts: false,
      restart: false
    });
  }
  _.merge(serviceConfigOverrides, _.pick(argv, ['entrypoint', 'localhost', 'user', 'workdir']));
  if (argv['volumes-from']) {
    _.merge(serviceConfigOverrides.containerVolumesFrom, ServiceHelpers.normalizeMultiArgs(argv['volumes-from']));
  }
  if (indexOf.call(args, '--restart') >= 0) {
    _.merge(serviceConfigOverrides, _.pick(argv, 'restart'));
  }
  if (indexOf.call(args, '--publish-all') >= 0 || indexOf.call(args, '-P') >= 0) {
    serviceConfigOverrides.publishPorts = argv['publish-all'];
  }
  ref1 = [].concat(argv.env || []);
  for (i = 0, len = ref1.length; i < len; i++) {
    envVar = ref1[i];
    ref2 = envVar.split('='), name = ref2[0], val = ref2[1];
    serviceConfigOverrides.env[name] = val;
  }
  if (argv.detach) {
    serviceConfigOverrides.attach = false;
  }
  if (argv.name != null) {
    serviceConfigOverrides.containerName = argv.name;
  }
  if (argv.volume != null) {
    volumes = ServiceHelpers.normalizeVolumeArgs(argv.volume);
    serviceConfigOverrides.binds = serviceConfigOverrides.binds.concat(volumes);
  }
  return {
    service: service,
    env: env,
    options: options,
    serviceConfigOverrides: serviceConfigOverrides
  };
};

go = function(docker, servicesConfig, services, options) {
  var service;
  service = services.pop();
  return startServices(docker, servicesConfig, services, options).then(function(completedServicesMap) {
    return startService(docker, servicesConfig[service], service, options, completedServicesMap).then(function(arg) {
      var container, resolution;
      container = arg.container, resolution = arg.resolution;
      return {
        container: container,
        resolution: resolution,
        completedServicesMap: completedServicesMap
      };
    });
  }).then(function(arg) {
    var completedServicesMap, container, primaryServiceConfig, resolution;
    container = arg.container, resolution = arg.resolution, completedServicesMap = arg.completedServicesMap;
    switch (resolution) {
      case 'unattached':
        return {
          statusCode: 0
        };
      case 'reload':
        options.reporter.message();
        options.reporter.message(chalk.gray((chalk.bold('Reload')) + " requested. Rechecking containers.\n"));
        primaryServiceConfig = servicesConfig[service];
        primaryServiceConfig.containerName || (primaryServiceConfig.containerName = completedServicesMap[service].containerName.replace(/^\//, ''));
        primaryServiceConfig.forceRecreate = false;
        return go(docker, servicesConfig, services.concat(service), options);
      case 'detach':
        return printDetachedMessage(container, options).then(function() {
          return {
            statusCode: null
          };
        });
      case 'stop':
        return DockerUtils.stopContainer(container).then(function() {
          return maybeRepairSourceOwnership(docker, servicesConfig, service, options);
        }).then(function() {
          return DockerUtils.removeContainer(container);
        }).then(function() {
          return {
            statusCode: 0
          };
        });
      case 'end':
        return maybeRepairSourceOwnership(docker, servicesConfig, service, options).then(function() {
          return finalizeContainer(container, options).then(function(arg1) {
            var statusCode;
            statusCode = arg1.statusCode;
            return {
              statusCode: statusCode
            };
          });
        });
      default:
        throw "UNKNOWN SERVICE RESOLUTION: " + resolution;
    }
  })["catch"](function(err) {
    var message;
    if ((err != null) && err !== '' && typeof err === 'string' || (err.json != null)) {
      message = ((err != null ? err.json : void 0) || (typeof err === 'string' ? err : void 0) || (err != null ? err.message : void 0) || 'Unknown error').trim();
      message = message.replace(/^Error: /, '');
      options.reporter.error(chalk.bold('Error:') + ' ' + message);
    }
    options.reporter.finish();
    if (err != null ? err.stack : void 0) {
      options.stderr.write(err != null ? err.stack : void 0);
    }
    return {
      statusCode: -1
    };
  });
};

module.exports = function(args, commandOptions, done) {
  var docker, env, globalConfig, options, primaryServiceConfig, ref, ref1, service, serviceConfigOverrides, services, servicesConfig, sighupHandler;
  ref = parseArgs(args), service = ref.service, env = ref.env, options = ref.options, serviceConfigOverrides = ref.serviceConfigOverrides;
  options = _.merge({}, commandOptions['globalOptions'], options);
  if (!((service != null) && !_.isEmpty(service))) {
    return help(args, commandOptions, done);
  }
  docker = new Docker();
  options.stdin = commandOptions.stdin || process.stdin;
  options.stderr = commandOptions.stderr || process.stderr;
  options.stdout = commandOptions.stdout || new OverlayOutputStream(process.stdout);
  options.reporter = commandOptions.reporter || new ConsoleReporter(options.stderr);
  options.stdinCommandInterceptor = new StdinCommandInterceptor(options.stdin);
  options.localhostForwarder = new LocalhostForwarder(docker.modem, options.reporter);
  if (!env) {
    throw "Missing env for service " + service + ". Format: <service>.<env>";
  }
  ref1 = ServiceHelpers.processConfig(commandOptions.config, env, options.add), globalConfig = ref1.globalConfig, servicesConfig = ref1.servicesConfig;
  primaryServiceConfig = servicesConfig[service];
  _.merge(primaryServiceConfig, serviceConfigOverrides);
  services = ServiceHelpers.generatePrereqServices(service, servicesConfig);
  sighupHandler = options.stdinCommandInterceptor.sighup.bind(options.stdinCommandInterceptor);
  process.on('SIGHUP', sighupHandler);
  return prepareServiceSource(docker, globalConfig, servicesConfig, service, env, options).then(function(arg) {
    var rsyncer;
    rsyncer = arg.rsyncer;
    return go(docker, servicesConfig, services, options)["finally"](function() {
      return rsyncer != null ? rsyncer.stop() : void 0;
    });
  }).then(function(arg) {
    var statusCode;
    statusCode = arg.statusCode;
    process.removeListener('SIGHUP', sighupHandler);
    options.stdinCommandInterceptor.stop();
    return done(statusCode);
  })["catch"](function(err) {
    console.error("UNCAUGHT EXCEPTION IN RUN COMMAND");
    console.error(err);
    if (err != null ? err.stack : void 0) {
      console.error(err != null ? err.stack : void 0);
    }
    return process.exit(255);
  });
};

module.exports.parseArgs = parseArgs;
