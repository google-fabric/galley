var RSVP, _, attachContainer, createContainer, downloadImage, inspectContainer, inspectImage, listContainers, listImages, pauseContainer, removeContainer, removeImage, resizeContainer, restartContainer, startContainer, stopContainer, unpauseContainer, url, waitContainer;

url = require('url');

_ = require('lodash');

RSVP = require('rsvp');

inspectImage = function(image) {
  return new RSVP.Promise(function(resolve, reject) {
    return image.inspect(function(err, info) {
      if (err) {
        return reject(err);
      } else {
        return resolve({
          image: image,
          info: info
        });
      }
    });
  });
};

removeImage = function(image, opts) {
  if (opts == null) {
    opts = {};
  }
  return new RSVP.Promise(function(resolve, reject) {
    return image.remove(opts, function(err) {
      if (err) {
        return reject(err);
      } else {
        return resolve();
      }
    });
  });
};

createContainer = function(docker, opts) {
  return new RSVP.Promise(function(resolve, reject) {
    return docker.createContainer(opts, function(err, container) {
      if (err) {
        return reject(err);
      } else {
        return resolve({
          container: container
        });
      }
    });
  });
};

inspectContainer = function(container) {
  return new RSVP.Promise(function(resolve, reject) {
    return container.inspect(function(err, info) {
      if (err) {
        return reject(err);
      } else {
        return resolve({
          container: container,
          info: info
        });
      }
    });
  });
};

startContainer = function(container, opts) {
  if (opts == null) {
    opts = {};
  }
  return new RSVP.Promise(function(resolve, reject) {
    return container.start(opts, function(err) {
      if (err) {
        return reject(err);
      } else {
        return resolve({
          container: container
        });
      }
    });
  });
};

stopContainer = function(container, opts) {
  if (opts == null) {
    opts = {};
  }
  return new RSVP.Promise(function(resolve, reject) {
    return container.stop(opts, function(err) {
      if (err) {
        return reject(err);
      } else {
        return resolve({
          container: container
        });
      }
    });
  });
};

restartContainer = function(container, opts) {
  if (opts == null) {
    opts = {};
  }
  return new RSVP.Promise(function(resolve, reject) {
    return container.restart(opts, function(err) {
      if (err) {
        return reject(err);
      } else {
        return resolve({
          container: container
        });
      }
    });
  });
};

pauseContainer = function(container, opts) {
  if (opts == null) {
    opts = {};
  }
  return new RSVP.Promise(function(resolve, reject) {
    return container.pause(opts, function(err) {
      if (err) {
        return reject(err);
      } else {
        return resolve({
          container: container
        });
      }
    });
  });
};

unpauseContainer = function(container, opts) {
  if (opts == null) {
    opts = {};
  }
  return new RSVP.Promise(function(resolve, reject) {
    return container.unpause(opts, function(err) {
      if (err) {
        return reject(err);
      } else {
        return resolve({
          container: container
        });
      }
    });
  });
};

attachContainer = function(container, opts) {
  return new RSVP.Promise(function(resolve, reject) {
    return container.attach(opts, function(err, stream) {
      if (err) {
        return reject(err);
      } else {
        return resolve({
          container: container,
          stream: stream
        });
      }
    });
  });
};

waitContainer = function(container) {
  return new RSVP.Promise(function(resolve, reject) {
    return container.wait(function(err, result) {
      if (err) {
        return reject(err);
      } else {
        return resolve({
          container: container,
          result: result
        });
      }
    });
  });
};

removeContainer = function(container, opts) {
  return new RSVP.Promise(function(resolve, reject) {
    return container.remove(opts, function(err) {
      if (err) {
        return reject(err);
      } else {
        return resolve();
      }
    });
  });
};

resizeContainer = function(container, ttyStream) {
  return new RSVP.Promise(function(resolve, reject) {
    var dimensions;
    dimensions = {
      h: ttyStream.rows,
      w: ttyStream.columns
    };
    if ((dimensions.h != null) && (dimensions.w != null)) {
      return container.resize(dimensions, function(err) {
        if (err) {
          return reject(err);
        } else {
          return resolve({
            container: container
          });
        }
      });
    } else {
      return resolve({
        container: container
      });
    }
  });
};

downloadImage = function(docker, imageName, authConfigFn, progressCb) {
  if (progressCb == null) {
    progressCb = function() {};
  }
  return new RSVP.Promise(function(resolve, reject) {
    var opts, repository;
    opts = {};
    if (imageName.indexOf('/') !== -1) {
      repository = imageName.split('/')[0];
      if (repository.indexOf('.') !== -1) {
        opts.authconfig = authConfigFn(repository);
      }
    }
    return docker.pull(imageName, opts, function(err, stream) {
      if (err) {
        return reject(err);
      }
      stream.on('data', function(byteBuffer) {
        var resp;
        resp = JSON.parse(byteBuffer.toString());
        if (resp.error != null) {
          reject(resp.error);
        }
        return progressCb(resp.progress || resp.status);
      });
      return stream.on('end', function() {
        return resolve();
      });
    });
  });
};

listContainers = function(docker, opts) {
  if (opts == null) {
    opts = {};
  }
  return new RSVP.Promise(function(resolve, reject) {
    return docker.listContainers(opts, function(err, infos) {
      if (err) {
        return reject(err);
      } else {
        return resolve({
          infos: infos
        });
      }
    });
  });
};

listImages = function(docker, opts) {
  if (opts == null) {
    opts = {};
  }
  return new RSVP.Promise(function(resolve, reject) {
    return docker.listImages(opts, function(err, infos) {
      if (err) {
        return reject(err);
      } else {
        return resolve({
          infos: infos
        });
      }
    });
  });
};

module.exports = {
  inspectImage: inspectImage,
  removeImage: removeImage,
  createContainer: createContainer,
  inspectContainer: inspectContainer,
  startContainer: startContainer,
  stopContainer: stopContainer,
  restartContainer: restartContainer,
  pauseContainer: pauseContainer,
  unpauseContainer: unpauseContainer,
  attachContainer: attachContainer,
  resizeContainer: resizeContainer,
  waitContainer: waitContainer,
  removeContainer: removeContainer,
  downloadImage: downloadImage,
  listContainers: listContainers,
  listImages: listImages
};
