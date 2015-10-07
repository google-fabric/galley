var _, formatEnvVariables, formatLinks, formatPortBindings, formatVolumes, formatVolumesFrom;

_ = require('lodash');

formatEnvVariables = function(envVars) {
  var name, out, value;
  out = [];
  for (name in envVars) {
    value = envVars[name];
    if (value != null) {
      out.push(name + "=" + value);
    }
  }
  return out;
};

formatLinks = function(links, containerNameMap) {
  var alias, containerName, i, len, link, results, service;
  results = [];
  for (i = 0, len = links.length; i < len; i++) {
    link = links[i];
    service = link.split(':')[0];
    alias = link.split(':')[1] || service;
    containerName = containerNameMap[service];
    results.push(containerName + ":" + alias);
  }
  return results;
};

formatPortBindings = function(ports) {
  var dst, exposedPorts, i, len, port, portBindings, ref, src;
  portBindings = {};
  exposedPorts = {};
  for (i = 0, len = ports.length; i < len; i++) {
    port = ports[i];
    ref = port.split(':'), dst = ref[0], src = ref[1];
    if (src) {
      portBindings[src + "/tcp"] = [
        {
          'HostPort': dst
        }
      ];
    } else {
      exposedPorts[dst + "/tcp"] = {};
    }
  }
  return {
    portBindings: portBindings,
    exposedPorts: exposedPorts
  };
};

formatVolumes = function(volumes) {
  return _.zipObject(_.map(volumes, function(volume) {
    return [volume, {}];
  }));
};

formatVolumesFrom = function(volumesFrom, containerNameMap) {
  var i, len, name, results;
  results = [];
  for (i = 0, len = volumesFrom.length; i < len; i++) {
    name = volumesFrom[i];
    results.push(containerNameMap[name] || name);
  }
  return results;
};

module.exports = {
  formatEnvVariables: formatEnvVariables,
  formatLinks: formatLinks,
  formatPortBindings: formatPortBindings,
  formatVolumes: formatVolumes,
  formatVolumesFrom: formatVolumesFrom
};
