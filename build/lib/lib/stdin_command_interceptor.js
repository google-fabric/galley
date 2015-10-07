var CTRL_C, CTRL_P, CTRL_Q, CTRL_R, StdinCommandInterceptor, events,
  extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  hasProp = {}.hasOwnProperty;

events = require('events');

CTRL_C = '\u0003';

CTRL_P = '\u0010';

CTRL_Q = '\u0011';

CTRL_R = '\u0012';

StdinCommandInterceptor = (function(superClass) {
  extend(StdinCommandInterceptor, superClass);

  function StdinCommandInterceptor(stdin) {
    this.stdin = stdin;
    this.stdinDataHandler = this.onStdinData.bind(this);
  }

  StdinCommandInterceptor.prototype.start = function(inputStream) {
    this.inputStream = inputStream;
    this.previousKey = null;
    if (this.stdin.isTTY) {
      this.stdin.setRawMode(true);
      this.inputStream.setEncoding('utf8');
      this.stdin.setEncoding('utf8');
      this.stdin.on('data', this.stdinDataHandler);
    } else {
      this.stdin.pipe(this.inputStream);
    }
    return this.inputStream._output.socket.on('close', (function(_this) {
      return function() {
        if (_this.inputStream && _this.stdin.readable) {
          return _this._trigger('detach');
        }
      };
    })(this));
  };

  StdinCommandInterceptor.prototype.stop = function() {
    var inputStream;
    if (!this.inputStream) {
      return;
    }
    inputStream = this.inputStream;
    this.inputStream = null;
    inputStream.destroy();
    if (this.stdin.isTTY) {
      this.stdin.removeListener('data', this.stdinDataHandler);
      return this.stdin.setRawMode(false);
    } else {
      return this.stdin.unpipe(inputStream);
    }
  };

  StdinCommandInterceptor.prototype.onStdinData = function(key) {
    if (this.previousKey === CTRL_P) {
      this.previousKey = null;
      switch (key) {
        case CTRL_C:
          return this._trigger('stop');
        case CTRL_P:
          return this.inputStream.write(CTRL_P);
        case CTRL_Q:
          return this._trigger('detach');
        case CTRL_R:
          return this._trigger('reload');
      }
    } else {
      this.previousKey = key;
      return setImmediate((function(_this) {
        return function() {
          var ref;
          return (ref = _this.inputStream) != null ? ref.write(key) : void 0;
        };
      })(this));
    }
  };

  StdinCommandInterceptor.prototype.sighup = function() {
    return this._trigger('reload');
  };

  StdinCommandInterceptor.prototype._trigger = function(command) {
    return this.emit('command', {
      command: command
    });
  };

  return StdinCommandInterceptor;

})(events.EventEmitter);

module.exports = StdinCommandInterceptor;
