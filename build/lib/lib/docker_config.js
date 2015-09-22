var _, fs, homeDir, path, url;

fs = require('fs');

path = require('path');

url = require('url');

_ = require('lodash');

homeDir = require('home-dir');

module.exports = {
  authConfig: function(host) {
    var authBuffer, config, configFile, dockerOneSevenConfig, e, hostConfig, password, ref, username;
    hostConfig = (function() {
      var error;
      try {
        dockerOneSevenConfig = path.resolve(homeDir(), '.docker/config.json');
        config = fs.existsSync(dockerOneSevenConfig) ? (configFile = fs.readFileSync(dockerOneSevenConfig), config = JSON.parse(configFile.toString()), config['auths']) : (configFile = fs.readFileSync(path.resolve(homeDir(), '.dockercfg')), JSON.parse(configFile.toString()));
        return config[host];
      } catch (error) {
        e = error;
        if ((e != null ? e.code : void 0) !== 'ENOENT') {
          throw e;
        }
      }
    })();
    if (hostConfig != null) {
      authBuffer = new Buffer(hostConfig.auth, 'base64');
      ref = authBuffer.toString().split(':'), username = ref[0], password = ref[1];
      return {
        username: username,
        password: password,
        serveraddress: host
      };
    }
  }
};
