var TestReporter, chalk;

chalk = require('chalk');

TestReporter = (function() {
  function TestReporter() {
    this.services = {};
    this.currentService = null;
  }

  TestReporter.prototype.startService = function(serviceName) {
    this.currentService = serviceName;
    this.services[this.currentService] = [];
    return this;
  };

  TestReporter.prototype.startTask = function(job) {
    this.lastTask = job;
    return this;
  };

  TestReporter.prototype.startProgress = function() {
    return {
      set: function() {},
      clear: function() {}
    };
  };

  TestReporter.prototype.succeedTask = function(msg) {
    if (msg == null) {
      msg = 'done!';
    }
    this.services[this.currentService].push(this.lastTask);
    this.lastTask = null;
    return this;
  };

  TestReporter.prototype.completeTask = function(msg) {
    if (this.lastTask) {
      this.services[this.currentService].push(this.lastTask);
    } else {
      this.services[this.currentService].push(msg);
    }
    this.lastTask = null;
    return this;
  };

  TestReporter.prototype.finish = function() {
    if (this.lastTask) {
      this.services[this.currentService].push(this.lastTask);
    }
    this.currentService = null;
    this.lastTask = null;
    return this;
  };

  TestReporter.prototype.error = function(err) {
    this.currentService = null;
    this.lastTask = null;
    this.lastError = err;
    return this;
  };

  TestReporter.prototype.message = function(msg) {
    this.currentService = null;
    this.lastTask = null;
    return this;
  };

  return TestReporter;

})();

module.exports = TestReporter;
