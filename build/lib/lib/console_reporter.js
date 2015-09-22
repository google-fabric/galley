var ConsoleReporter, ProgressLine, chalk;

chalk = require('chalk');

ProgressLine = require('./progress_line');

ConsoleReporter = (function() {
  function ConsoleReporter(stream) {
    this.stream = stream;
    this.inLine = false;
  }

  ConsoleReporter.prototype.maybeSpace = function() {
    if (this.inLine) {
      return this.stream.write(' ');
    }
  };

  ConsoleReporter.prototype.startService = function(serviceName) {
    this.stream.write(chalk.blue(serviceName + ':'));
    this.inLine = true;
    return this;
  };

  ConsoleReporter.prototype.startTask = function(job) {
    this.maybeSpace();
    this.stream.write(chalk.gray(job + '…'));
    this.inLine = true;
    return this;
  };

  ConsoleReporter.prototype.startProgress = function(msg) {
    this.maybeSpace();
    if (msg) {
      this.stream.write(msg + ' ');
    }
    this.inLine = true;
    return new ProgressLine(this.stream, chalk.gray);
  };

  ConsoleReporter.prototype.succeedTask = function(msg) {
    if (msg == null) {
      msg = 'done!';
    }
    this.maybeSpace();
    this.stream.write(chalk.green(msg));
    return this;
  };

  ConsoleReporter.prototype.completeTask = function(msg) {
    this.maybeSpace();
    this.stream.write(chalk.cyan(msg));
    return this;
  };

  ConsoleReporter.prototype.finish = function() {
    if (this.inLine) {
      this.stream.write('\n');
    }
    this.inLine = false;
    return this;
  };

  ConsoleReporter.prototype.error = function(err) {
    this.maybeSpace();
    this.stream.write(chalk.red(err) + '\n');
    this.inLine = false;
    return this;
  };

  ConsoleReporter.prototype.message = function(msg) {
    if (msg == null) {
      msg = '';
    }
    this.stream.write(msg + '\n');
    this.inLine = false;
    return this;
  };

  return ConsoleReporter;

})();

module.exports = ConsoleReporter;
