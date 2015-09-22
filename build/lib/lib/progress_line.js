var ProgressLine, spin;

spin = require('term-spinner');

module.exports = ProgressLine = (function() {
  function ProgressLine(stream, colorFn) {
    this.stream = stream;
    this.colorFn = colorFn != null ? colorFn : function(v) {
      return v;
    };
    this.spinner = spin["new"]();
    this.currentStr = '';
  }

  ProgressLine.prototype.set = function(str) {
    var nextStr;
    if (!this.stream.isTTY) {
      return this.stream.write(str);
    }
    this.spinner.next();
    this.stream.moveCursor(-this.currentStr.length, 0);
    this.currentStr = this.currentStr.trim();
    nextStr = (str != null ? str[0] : void 0) === '[' ? str : this.spinner.current + " " + str;
    if (this.currentStr.length > nextStr.length) {
      nextStr = nextStr + Array(this.currentStr.length - nextStr.length + 1).join(' ');
    }
    this.stream.write(this.colorFn(nextStr));
    return this.currentStr = nextStr;
  };

  ProgressLine.prototype.clear = function() {
    if (!this.stream.isTTY) {
      return;
    }
    this.set('');
    return this.stream.moveCursor(-this.currentStr.length - 1, 0);
  };

  return ProgressLine;

})();
