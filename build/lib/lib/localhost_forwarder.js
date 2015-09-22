var LocalhostForwarder, LocalhostForwarderReceipt, tcpProxy;

tcpProxy = require('tcp-proxy');

LocalhostForwarder = (function() {
  function LocalhostForwarder(dockerConfig, reporter) {
    this.dockerConfig = dockerConfig;
    this.reporter = reporter;
  }

  LocalhostForwarder.prototype.forward = function(ports) {
    var port, server, servers;
    if (this.dockerConfig.socketPath != null) {
      return;
    }
    servers = (function() {
      var i, len, results;
      results = [];
      for (i = 0, len = ports.length; i < len; i++) {
        port = ports[i];
        server = tcpProxy.createServer({
          target: {
            host: this.dockerConfig.host,
            port: port
          }
        });
        server.listen(port);
        server.on('error', (function(_this) {
          return function(port) {
            return function(err) {
              return _this.reporter.error("Failure proxying to " + _this.dockerConfig.host + ":" + port + ": " + err);
            };
          };
        })(this)(port));
        results.push(server);
      }
      return results;
    }).call(this);
    return new LocalhostForwarderReceipt(servers);
  };

  return LocalhostForwarder;

})();

LocalhostForwarderReceipt = (function() {
  function LocalhostForwarderReceipt(servers) {
    this.servers = servers;
  }

  LocalhostForwarderReceipt.prototype.stop = function() {
    var i, len, ref, server;
    ref = this.servers;
    for (i = 0, len = ref.length; i < len; i++) {
      server = ref[i];
      server.close();
    }
    return this.servers = [];
  };

  return LocalhostForwarderReceipt;

})();

module.exports = LocalhostForwarder;
