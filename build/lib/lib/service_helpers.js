var DEFAULT_SERVICE_CONFIG, ENV_COLLAPSED_ARRAY_CONFIG_KEYS, RSVP, _, addDefaultNames, collapseEnvironment, collapseServiceConfigEnv, combineAddons, envsFromServiceConfig, generatePrereqServices, generatePrereqsRecursively, listAddons, listServicesWithEnvs, lookupEnvArray, lookupEnvValue, normalizeMultiArgs, normalizeVolumeArgs, path, processConfig;

RSVP = require('rsvp');

_ = require('lodash');

path = require('path');

DEFAULT_SERVICE_CONFIG = {
  binds: [],
  command: null,
  entrypoint: null,
  env: {},
  image: null,
  links: [],
  ports: [],
  restart: false,
  source: null,
  stateful: false,
  user: '',
  volumesFrom: []
};

ENV_COLLAPSED_ARRAY_CONFIG_KEYS = ['links', 'ports', 'volumesFrom'];

normalizeMultiArgs = function(addonOptions) {
  var toReturn;
  toReturn = addonOptions;
  if (_.isString(toReturn)) {
    toReturn = [toReturn];
  } else if (_.isUndefined(toReturn)) {
    toReturn = [];
  }
  return _.flatten(_.map(toReturn, function(val) {
    if (val.indexOf(",") > -1) {
      return _.filter(val.split(","), function(val) {
        return val.length > 0;
      });
    } else {
      return val;
    }
  }));
};

normalizeVolumeArgs = function(volumeOptions) {
  var volumes;
  volumes = _.isArray(volumeOptions) ? volumeOptions : [volumeOptions];
  return _.map(volumes, function(volume) {
    var container_path, host_path, ref;
    ref = volume.split(':'), host_path = ref[0], container_path = ref[1];
    return (path.resolve(host_path)) + ":" + container_path;
  });
};

lookupEnvValue = function(hash, env, defaultValue) {
  var namespace, ref, val;
  if (defaultValue === void 0) {
    defaultValue = [];
  }
  ref = env.split('.'), env = ref[0], namespace = ref[1];
  val = hash[env + "." + namespace] || hash[env];
  if (val != null) {
    return val;
  } else {
    return defaultValue;
  }
};

lookupEnvArray = function(value, env) {
  value = value || [];
  if (_.isArray(value)) {
    return value;
  } else {
    return lookupEnvValue(value, env);
  }
};

collapseServiceConfigEnv = function(serviceConfig, env) {
  var collapsedServiceConfig;
  collapsedServiceConfig = _.mapValues(serviceConfig, function(value, key) {
    if (ENV_COLLAPSED_ARRAY_CONFIG_KEYS.indexOf(key) !== -1) {
      return collapseEnvironment(value, env, []);
    } else if (key === 'env') {
      return _.mapValues(value, function(envValue, envKey) {
        return collapseEnvironment(envValue, env, null);
      });
    } else {
      return value;
    }
  });
  return collapsedServiceConfig;
};

combineAddons = function(service, env, serviceConfig, requestedAddons, globalAddons) {
  var addon, addonEnv, addonName, addonValue, i, j, key, len, len1, serviceAddon;
  for (i = 0, len = requestedAddons.length; i < len; i++) {
    addonName = requestedAddons[i];
    addon = globalAddons[addonName];
    if (addon == null) {
      throw "Addon " + addonName + " not found in ADDONS list in Galleyfile";
    }
    serviceAddon = addon[service];
    if (serviceAddon != null) {
      for (j = 0, len1 = ENV_COLLAPSED_ARRAY_CONFIG_KEYS.length; j < len1; j++) {
        key = ENV_COLLAPSED_ARRAY_CONFIG_KEYS[j];
        if (serviceAddon[key] != null) {
          addonValue = collapseEnvironment(serviceAddon[key], env, []);
          serviceConfig[key] = serviceConfig[key].concat(addonValue);
        }
        if (serviceAddon.env != null) {
          addonEnv = _.mapValues(serviceAddon.env, function(envValue, envKey) {
            return collapseEnvironment(envValue, env, null);
          });
          serviceConfig.env = _.merge({}, serviceConfig.env, addonEnv);
        }
      }
    }
  }
  return serviceConfig;
};

addDefaultNames = function(globalConfig, service, env, serviceConfig) {
  serviceConfig.name = service;
  serviceConfig.containerName = service + "." + env;
  serviceConfig.image || (serviceConfig.image = _.compact([globalConfig.registry, service]).join('/'));
  return serviceConfig;
};

processConfig = function(galleyfileValue, env, requestedAddons) {
  var globalAddons, globalConfig, servicesConfig;
  globalConfig = galleyfileValue.CONFIG || {};
  globalAddons = galleyfileValue.ADDONS || {};
  if (globalConfig.rsync == null) {
    globalConfig.rsync = {
      image: 'galley/rsync',
      module: 'root'
    };
  }
  servicesConfig = _.mapValues(galleyfileValue, function(serviceConfig, service) {
    if (service === 'CONFIG') {
      return;
    }
    serviceConfig = _.merge({}, DEFAULT_SERVICE_CONFIG, serviceConfig);
    serviceConfig = collapseServiceConfigEnv(serviceConfig, env);
    serviceConfig = combineAddons(service, env, serviceConfig, requestedAddons, globalAddons);
    serviceConfig = addDefaultNames(globalConfig, service, env, serviceConfig);
    return serviceConfig;
  });
  delete servicesConfig.CONFIG;
  return {
    globalConfig: globalConfig,
    servicesConfig: servicesConfig
  };
};

collapseEnvironment = function(configValue, env, defaultValue) {
  if (_.isObject(configValue) && !_.isArray(configValue)) {
    return lookupEnvValue(configValue, env, defaultValue);
  } else {
    if (configValue != null) {
      return configValue;
    } else {
      return defaultValue;
    }
  }
};

envsFromServiceConfig = function(serviceConfig) {
  var definedEnvs, envEnvs, parametrizeableKey, value, variable;
  definedEnvs = (function() {
    var ref, results;
    ref = _.pick(serviceConfig, ['links', 'ports', 'volumesFrom']);
    results = [];
    for (parametrizeableKey in ref) {
      value = ref[parametrizeableKey];
      if (!value || _.isArray(value)) {
        results.push([]);
      } else {
        results.push(_.keys(value));
      }
    }
    return results;
  })();
  envEnvs = (function() {
    var ref, results;
    ref = serviceConfig['env'];
    results = [];
    for (variable in ref) {
      value = ref[variable];
      if (_.isArray(value) || _.isString(value)) {
        results.push([]);
      } else {
        results.push(_.keys(value));
      }
    }
    return results;
  })();
  definedEnvs = definedEnvs.concat(envEnvs);
  return _.unique(_.flatten(definedEnvs));
};

listServicesWithEnvs = function(galleyfileValue) {
  var serviceList;
  serviceList = _.mapValues(galleyfileValue, function(serviceConfig, service) {
    if (service === 'CONFIG' || service === 'ADDONS') {
      return;
    }
    return envsFromServiceConfig(serviceConfig);
  });
  delete serviceList.CONFIG;
  delete serviceList.ADDONS;
  return serviceList;
};

listAddons = function(galleyfileValue) {
  var addons;
  addons = galleyfileValue['ADDONS'] || {};
  return _.keys(addons);
};

generatePrereqServices = function(service, servicesConfig) {
  return _.uniq(generatePrereqsRecursively(service, servicesConfig).reverse());
};

generatePrereqsRecursively = function(service, servicesConfig, pendingServices, foundServices) {
  var links, nextFoundServices, prereqs, serviceConfig, volumesFroms;
  if (pendingServices == null) {
    pendingServices = [];
  }
  if (foundServices == null) {
    foundServices = [];
  }
  nextFoundServices = foundServices.concat(service);
  serviceConfig = servicesConfig[service];
  if (!serviceConfig) {
    throw "Missing config for service: " + service;
  }
  links = serviceConfig.links;
  volumesFroms = serviceConfig.volumesFrom;
  prereqs = links.concat(volumesFroms);
  _.forEach(prereqs, function(prereqName) {
    var circularIndex, dependencyServices, nextPendingServices, prereqService;
    prereqService = prereqName.split(':')[0];
    if ((circularIndex = pendingServices.indexOf(prereqService)) !== -1) {
      dependencyServices = foundServices.slice(circularIndex);
      dependencyServices.push(service, prereqService);
      throw "Circular dependency for " + prereqService + ": " + (dependencyServices.join(' -> '));
    }
    nextPendingServices = pendingServices.concat(service);
    return nextFoundServices = generatePrereqsRecursively(prereqService, servicesConfig, nextPendingServices, nextFoundServices);
  });
  return nextFoundServices;
};

module.exports = {
  DEFAULT_SERVICE_CONFIG: DEFAULT_SERVICE_CONFIG,
  normalizeMultiArgs: normalizeMultiArgs,
  normalizeVolumeArgs: normalizeVolumeArgs,
  addDefaultNames: addDefaultNames,
  generatePrereqServices: generatePrereqServices,
  collapseEnvironment: collapseEnvironment,
  combineAddons: combineAddons,
  collapseServiceConfigEnv: collapseServiceConfigEnv,
  processConfig: processConfig,
  listServicesWithEnvs: listServicesWithEnvs,
  listAddons: listAddons
};
