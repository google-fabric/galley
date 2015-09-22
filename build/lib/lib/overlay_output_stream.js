var OverlayOutputStream, _, charm, stream,
  extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  hasProp = {}.hasOwnProperty;

_ = require('lodash');

charm = require('charm');

stream = require('stream');

OverlayOutputStream = (function(superClass) {
  extend(OverlayOutputStream, superClass);

  function OverlayOutputStream(stream1, options) {
    var handleResize;
    this.stream = stream1;
    OverlayOutputStream.__super__.constructor.call(this, options);
    this.charm = charm(this.stream);
    this.isTTY = this.stream.isTTY;
    this.statusMessage = '';
    this.currentOverlayText = '';
    this.columns = this.stream.columns;
    this.rows = this.stream.rows;
    this.lastStreamColumns = this.stream.columns;
    handleResize = (function(_this) {
      return function() {
        _this.writeOverlay();
        _this.columns = _this.stream.columns;
        _this.rows = _this.stream.rows;
        return _this.emit('resize');
      };
    })(this);
    this.stream.on('resize', _.debounce(handleResize, 100));
    this.stream.on('drain', (function(_this) {
      return function() {
        return _this.emit('drain');
      };
    })(this));
  }

  OverlayOutputStream.prototype.setOverlayStatus = function(status) {
    this.statusMessage = status;
    if (this.hasOverlay) {
      return this.writeOverlay();
    }
  };

  OverlayOutputStream.prototype.flashOverlayMessage = function(message) {
    if (this.unsetFlashTimeout) {
      clearTimeout(this.unsetFlashTimeout);
    }
    this.unsetFlashTimeout = setTimeout(this.unsetOverlayFlash.bind(this), 2000);
    this.flashMessage = message;
    return this.writeOverlay();
  };

  OverlayOutputStream.prototype.unsetOverlayFlash = function() {
    this.flashMessage = null;
    return this.writeOverlay();
  };

  OverlayOutputStream.prototype.clearOverlay = function() {
    var overlayDidWrap, widthOnLine;
    if (!this.hasOverlay) {
      return;
    }
    this.charm.push(true);
    widthOnLine = this.currentOverlayText.length + (this.stream.columns - this.lastStreamColumns) + 1;
    overlayDidWrap = this.lastStreamColumns > this.stream.columns + 1;
    this.lastStreamColumns = this.stream.columns;
    this.charm.position(this.stream.columns - widthOnLine, this.stream.rows);
    if (overlayDidWrap) {
      this.charm.up(1);
    }
    this.charm["delete"]('char', this.currentOverlayText.length + 1);
    if (overlayDidWrap) {
      this.charm.down(1);
      this.charm["delete"]('line', 1);
    }
    this.charm.pop(true);
    if (overlayDidWrap) {
      this.charm.scroll(-1);
      return this.charm.down(1);
    }
  };

  OverlayOutputStream.prototype.writeOverlay = function() {
    var text;
    if (!this.isTTY) {
      return;
    }
    this.clearOverlay();
    this.charm.push(true);
    if (this.flashMessage) {
      text = this.flashMessage;
      this.charm.background(13);
      this.charm.foreground('white');
    } else if (this.statusMessage) {
      this.charm.foreground(13);
      this.charm.background('white');
      text = this.statusMessage;
    } else {
      this.currentOverlayText = '';
      this.charm.pop(true);
      return;
    }
    this.currentOverlayText = text ? " " + text + " " : '';
    this.charm.position(this.stream.columns - this.currentOverlayText.length, this.stream.rows);
    this.charm.write(this.currentOverlayText);
    this.charm.pop(true);
    return this.hasOverlay = true;
  };

  OverlayOutputStream.prototype._write = function(chunk, encoding, cb) {
    var redraw, ret;
    redraw = chunk.toString().indexOf('\n') !== -1;
    if (redraw) {
      this.clearOverlay();
    }
    ret = this.stream.write(chunk, encoding, cb);
    if (redraw) {
      this.writeOverlay();
    }
    return ret;
  };

  OverlayOutputStream.prototype.end = function() {
    this.clearOverlay();
    return OverlayOutputStream.__super__.end.apply(this, arguments);
  };

  return OverlayOutputStream;

})(stream.Writable);

module.exports = OverlayOutputStream;
