var _, fs, homeDir, path, url;

fs = require('fs');

path = require('path');

url = require('url');

_ = require('lodash');

homeDir = require('home-dir');

module.exports = {
  connectionConfig: function() {
    var certPath, dockerOpts, hostUrl;
    hostUrl = url.parse(process.env.DOCKER_HOST || '');
    dockerOpts = hostUrl.hostname ? {
      host: hostUrl.hostname,
      port: hostUrl.port
    } : {
      socketPath: process.env.DOCKER_HOST || '/var/run/docker.sock'
    };
    if ((certPath = process.env.DOCKER_CERT_PATH)) {
      _.merge(dockerOpts, {
        protocol: 'https',
        ca: fs.readFileSync(certPath + "/ca.pem"),
        cert: fs.readFileSync(certPath + "/cert.pem"),
        key: fs.readFileSync(certPath + "/key.pem")
      });
    }
    return dockerOpts;
  },
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
