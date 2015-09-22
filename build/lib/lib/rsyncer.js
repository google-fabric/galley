var RSVP, Rsync, Rsyncer, WATCH_CHILD_PATH, _, child_process, chokidar, fs, path;

_ = require('lodash');

child_process = require('child_process');

chokidar = require('chokidar');

fs = require('fs');

path = require('path');

RSVP = require('rsvp');

Rsync = require('rsync');

WATCH_CHILD_PATH = path.resolve(__dirname, '../bin/watch.js');

Rsyncer = (function() {
  function Rsyncer(options) {
    var dockerignorePath;
    this.source = options.src;
    this.syncing = false;
    this.needsResync = false;
    this.watching = false;
    this.watchChild = null;
    this.activityCb = null;
    this.rsync = Rsync.build({
      source: options.src + "/",
      destination: "rsync://" + options.host + ":" + options.port + "/" + options.module + options.dest + "/",
      flags: 'av'
    }).set('delete');
    dockerignorePath = path.resolve(options.src, '.dockerignore');
    if (fs.existsSync(dockerignorePath)) {
      this.rsync.set('exclude-from', dockerignorePath);
    }
  }

  Rsyncer.prototype.sync = function(progressCb) {
    return new RSVP.Promise((function(_this) {
      return function(resolve, reject) {
        var completionHandler, statusLines, stdoutHandler;
        statusLines = [];
        _this.syncing = true;
        completionHandler = function(error, code, cmd) {
          var fileStatusLines, pathStatusLines;
          _this.syncing = false;
          pathStatusLines = statusLines.slice(2, -2);
          fileStatusLines = _.filter(pathStatusLines, function(line) {
            return line.slice(-1) !== '/';
          });
          if (error) {
            return reject(error);
          } else {
            return resolve(fileStatusLines);
          }
        };
        stdoutHandler = function(data) {
          var newStatusLines;
          newStatusLines = _.filter(data.toString().split('\n'), function(line) {
            return line !== '';
          });
          statusLines = statusLines.concat(newStatusLines);
          return progressCb(newStatusLines);
        };
        return _this.rsync.execute(completionHandler, stdoutHandler);
      };
    })(this));
  };

  Rsyncer.prototype.scheduleSync = function(progressCb, accumFiles) {
    var syncPromise;
    if (accumFiles == null) {
      accumFiles = [];
    }
    if (this.syncing) {
      this.needsResync = true;
      return;
    }
    return syncPromise = this.sync(progressCb).then((function(_this) {
      return function(newFiles) {
        accumFiles.push.apply(accumFiles, newFiles);
        if (_this.needsResync) {
          _this.needsResync = false;
          return _this.scheduleSync(progressCb, accumFiles);
        } else {
          return accumFiles;
        }
      };
    })(this));
  };

  Rsyncer.prototype.watch = function(activityCb) {
    this.activityCb = activityCb != null ? activityCb : function() {};
    process.nextTick(this.activityCb.bind(null, 'watching', this.source, null, null));
    this.startWatchChild();
    process.once('exit', this.stop.bind(this));
    return process.once('uncaughtException', (function(_this) {
      return function(error) {
        if (process.listeners('uncaughtException').length === 0) {
          _this.stop();
          throw error;
        }
      };
    })(this));
  };

  Rsyncer.prototype.startWatchChild = function() {
    this.watching = true;
    this.watchChild = child_process.fork(WATCH_CHILD_PATH, [this.source], {
      silent: true
    });
    this.watchChild.on('message', (function(_this) {
      return function(msg) {
        switch (msg) {
          case 'change':
            return _this.receivedChange();
        }
      };
    })(this));
    return this.watchChild.on('exit', (function(_this) {
      return function() {
        if (!_this.watching) {
          return;
        }
        _this.startWatchChild();
        return _this.receivedChange();
      };
    })(this));
  };

  Rsyncer.prototype.receivedChange = function() {
    var syncPromise;
    syncPromise = this.scheduleSync(this.activityCb.bind(null, 'syncing', this.source, null, null));
    if (syncPromise) {
      this.activityCb('changed', this.source, null, null);
      return syncPromise.then((function(_this) {
        return function(files) {
          _this.activityCb('synched', _this.source, files, null);
          return _this.activityCb('watching', _this.source, null, null);
        };
      })(this))["catch"]((function(_this) {
        return function(err) {
          return _this.activityCb('error', _this.source, null, err);
        };
      })(this));
    }
  };

  Rsyncer.prototype.stop = function() {
    var ref;
    this.watching = false;
    if ((ref = this.watchChild) != null) {
      ref.kill('SIGTERM');
    }
    this.watchChild = null;
    return this.activityCb = null;
  };

  return Rsyncer;

})();

module.exports = Rsyncer;
