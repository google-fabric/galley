var ServiceHelpers, _, expect;

expect = require('expect');

_ = require('lodash');

ServiceHelpers = require('../lib/lib/service_helpers');

describe('normalizeMultiArgs', function() {
  describe('with a non-delimited string', function() {
    return it('should be an array with one value', function() {
      return expect(ServiceHelpers.normalizeMultiArgs('beta')).toEqual(['beta']);
    });
  });
  describe('with a delimited string with two values', function() {
    return it('should be an array with two values', function() {
      return expect(ServiceHelpers.normalizeMultiArgs('beta,other')).toEqual(['beta', 'other']);
    });
  });
  describe('with a delimited string with a bad leading comma', function() {
    return it('should be an array with one value', function() {
      return expect(ServiceHelpers.normalizeMultiArgs(',other')).toEqual(['other']);
    });
  });
  describe('with a delimited string with a bad trailing comma', function() {
    return it('should be an array with one value', function() {
      return expect(ServiceHelpers.normalizeMultiArgs('beta,')).toEqual(['beta']);
    });
  });
  describe('with an array with one value', function() {
    return it('should be an array with one value', function() {
      return expect(ServiceHelpers.normalizeMultiArgs(['beta'])).toEqual(['beta']);
    });
  });
  describe('with an array with one value', function() {
    return it('should be an array with one value', function() {
      return expect(ServiceHelpers.normalizeMultiArgs(['beta'])).toEqual(['beta']);
    });
  });
  describe('with an array with two values', function() {
    return it('should be an array with two values', function() {
      return expect(ServiceHelpers.normalizeMultiArgs(['beta', 'other'])).toEqual(['beta', 'other']);
    });
  });
  return describe('with an array with two values, one of which is delimited', function() {
    return it('should be an array with three values', function() {
      return expect(ServiceHelpers.normalizeMultiArgs(['beta', 'other,third'])).toEqual(['beta', 'other', 'third']);
    });
  });
});

describe('normalizeVolumeArgs', function() {
  it('handles a single value', function() {
    return expect(ServiceHelpers.normalizeVolumeArgs('/host:/container')).toEqual(['/host:/container']);
  });
  it('handles multiple values', function() {
    var volumes;
    volumes = ['/host1:/container1', '/host2:/container2'];
    return expect(ServiceHelpers.normalizeVolumeArgs(volumes)).toEqual(volumes);
  });
  return it('resolves relative paths', function() {
    return expect(ServiceHelpers.normalizeVolumeArgs(['host:/container'])).toEqual([(process.cwd()) + "/host:/container"]);
  });
});

describe('generatePrereqServices', function() {
  describe('generates simple dependency chain', function() {
    var config;
    config = {
      service: {
        links: ['service_two'],
        volumesFrom: []
      },
      service_two: {
        links: ['service_three'],
        volumesFrom: []
      },
      service_three: {
        links: ['service_four'],
        volumesFrom: ['service_five']
      },
      service_four: {
        links: [],
        volumesFrom: []
      },
      service_five: {
        links: [],
        volumesFrom: []
      }
    };
    return it('should generate correctly ordered list', function() {
      return expect(ServiceHelpers.generatePrereqServices('service', config)).toEqual(['service_five', 'service_four', 'service_three', 'service_two', 'service']);
    });
  });
  describe('does not have duplicate service entries, keeps the earliest', function() {
    var config;
    config = {
      service: {
        links: ['service_two'],
        volumesFrom: []
      },
      service_two: {
        links: ['service_three', 'service_four'],
        volumesFrom: []
      },
      service_three: {
        links: ['service_four'],
        volumesFrom: []
      },
      service_four: {
        links: [],
        volumesFrom: []
      }
    };
    return it('should generate correctly ordered list', function() {
      return expect(ServiceHelpers.generatePrereqServices('service', config)).toEqual(['service_four', 'service_three', 'service_two', 'service']);
    });
  });
  return describe('fails on circular dependency', function() {
    var config;
    config = {
      service: {
        links: ['service_another']
      },
      service_another: {
        links: ['service']
      }
    };
    return it('should throw', function() {
      return expect(function() {
        return ServiceHelpers.generatePrereqServices('service', config);
      }).toThrow('Circular dependency for service: service -> service_another -> service');
    });
  });
});

describe('collapseEnvironment', function() {
  describe('not parameterized', function() {
    var CONFIG_ARRAY_VALUE, CONFIG_STRING_VALUE;
    CONFIG_STRING_VALUE = 'foo';
    CONFIG_ARRAY_VALUE = ['foo', 'bar'];
    it('does not modify a string', function() {
      return expect(ServiceHelpers.collapseEnvironment(CONFIG_STRING_VALUE, 'dev')).toEqual(CONFIG_STRING_VALUE);
    });
    return it('does not modify an array', function() {
      return expect(ServiceHelpers.collapseEnvironment(CONFIG_ARRAY_VALUE, 'dev')).toEqual(CONFIG_ARRAY_VALUE);
    });
  });
  return describe('parameterized', function() {
    var CONFIG_VALUE;
    CONFIG_VALUE = {
      'dev': 'foo',
      'test': 'bar',
      'test.cucumber': 'baz'
    };
    it('returns defaultValue when env is missing', function() {
      return expect(ServiceHelpers.collapseEnvironment(CONFIG_VALUE, 'prod', ['default'])).toEqual(['default']);
    });
    it('finds named environment', function() {
      return expect(ServiceHelpers.collapseEnvironment(CONFIG_VALUE, 'dev', null)).toEqual('foo');
    });
    it('finds namespaced environment', function() {
      return expect(ServiceHelpers.collapseEnvironment(CONFIG_VALUE, 'test.cucumber', null)).toEqual('baz');
    });
    return it('falls back when namespace is missing', function() {
      return expect(ServiceHelpers.collapseEnvironment(CONFIG_VALUE, 'dev.cucumber', null)).toEqual('foo');
    });
  });
});

describe('collapseServiceConfigEnv', function() {
  describe('array parameterization', function() {
    var CONFIG;
    CONFIG = {
      image: 'my-image',
      links: {
        'dev': ['service'],
        'dev.namespace': ['better-service'],
        'test': ['mock-service']
      },
      ports: {
        'dev': ['3000']
      },
      volumesFrom: {
        'test': ['container']
      }
    };
    return it('collapses down to just the environment', function() {
      return expect(ServiceHelpers.collapseServiceConfigEnv(CONFIG, 'dev.namespace')).toEqual({
        image: 'my-image',
        links: ['better-service'],
        ports: ['3000'],
        volumesFrom: []
      });
    });
  });
  return describe('env parameterization', function() {
    var CONFIG;
    CONFIG = {
      env: {
        'HOSTNAME': 'docker',
        'NOTHING': '',
        'TEST_ONLY_VALUE': {
          'test': 'true'
        },
        'RAILS_ENV': {
          'dev': 'development',
          'test': 'test'
        }
      }
    };
    return it('paramerizes the env variables', function() {
      return expect(ServiceHelpers.collapseServiceConfigEnv(CONFIG, 'dev.namespace')).toEqual({
        env: {
          'HOSTNAME': 'docker',
          'NOTHING': '',
          'TEST_ONLY_VALUE': null,
          'RAILS_ENV': 'development'
        }
      });
    });
  });
});

describe('combineAddons', function() {
  return describe('addons', function() {
    describe('array parameter merging', function() {
      var EXPECTED;
      EXPECTED = {
        links: ['database', 'addon-service']
      };
      describe('without env', function() {
        var ADDONS, CONFIG;
        ADDONS = {
          'my-addon': {
            'service': {
              links: ['addon-service']
            }
          }
        };
        CONFIG = {
          links: ['database']
        };
        return it('merges addons array parameters with addon', function() {
          return expect(ServiceHelpers.combineAddons('service', 'dev', CONFIG, ['my-addon'], ADDONS)).toEqual(EXPECTED);
        });
      });
      describe('with addon env', function() {
        var ADDONS, CONFIG;
        ADDONS = {
          'my-addon': {
            'service': {
              links: {
                'dev': ['addon-service']
              }
            }
          }
        };
        CONFIG = {
          links: ['database']
        };
        return it('merges addons array parameters with addon env', function() {
          return expect(ServiceHelpers.combineAddons('service', 'dev', CONFIG, ['my-addon'], ADDONS)).toEqual(EXPECTED);
        });
      });
      return describe('with addon namespaced env', function() {
        var ADDONS, CONFIG;
        ADDONS = {
          'my-addon': {
            'service': {
              links: {
                'dev.namespace': ['addon-service']
              }
            }
          }
        };
        CONFIG = {
          links: ['database']
        };
        return it('merges addons array parameters with namespaced addon env', function() {
          return expect(ServiceHelpers.combineAddons('service', 'dev.namespace', CONFIG, ['my-addon'], ADDONS)).toEqual(EXPECTED);
        });
      });
    });
    return describe('env parameter merging', function() {
      describe('with no base env', function() {
        var ADDONS, CONFIG;
        ADDONS = {
          'my-addon': {
            'service': {
              env: {
                'HOSTNAME': 'docker-addon',
                'CUSTOM': {
                  'dev.namespace': 'custom-value'
                }
              }
            }
          }
        };
        CONFIG = {};
        return it('parametrizes the env variables', function() {
          return expect(ServiceHelpers.combineAddons('service', 'dev.namespace', CONFIG, ['my-addon'], ADDONS)).toEqual({
            env: {
              'HOSTNAME': 'docker-addon',
              'CUSTOM': 'custom-value'
            }
          });
        });
      });
      describe('with a base env', function() {
        var ADDONS, CONFIG;
        ADDONS = {
          'my-addon': {
            'service': {
              env: {
                'HOSTNAME': 'docker-addon',
                'CUSTOM': {
                  'dev.namespace': 'custom-value'
                }
              }
            }
          }
        };
        CONFIG = {
          env: {
            'HOSTNAME': 'docker',
            'TEST_ONLY_VALUE': null,
            'RAILS_ENV': 'development'
          }
        };
        return it('parametrizes the env variables', function() {
          return expect(ServiceHelpers.combineAddons('service', 'dev.namespace', CONFIG, ['my-addon'], ADDONS)).toEqual({
            env: {
              'HOSTNAME': 'docker-addon',
              'TEST_ONLY_VALUE': null,
              'RAILS_ENV': 'development',
              'CUSTOM': 'custom-value'
            }
          });
        });
      });
      return describe('with multiple addons', function() {
        var ADDONS, CONFIG;
        ADDONS = {
          'my-addon': {
            'service': {
              env: {
                'HOSTNAME': 'docker-addon'
              }
            }
          },
          'my-second-addon': {
            'service': {
              env: {
                'CUSTOM': {
                  'dev.namespace': 'custom-value'
                }
              }
            }
          }
        };
        CONFIG = {
          env: {
            'HOSTNAME': 'docker',
            'TEST_ONLY_VALUE': null,
            'RAILS_ENV': 'development'
          }
        };
        return it('paramerizes the env variables', function() {
          return expect(ServiceHelpers.combineAddons('service', 'dev.namespace', CONFIG, ['my-addon', 'my-second-addon'], ADDONS)).toEqual({
            env: {
              'HOSTNAME': 'docker-addon',
              'TEST_ONLY_VALUE': null,
              'RAILS_ENV': 'development',
              'CUSTOM': 'custom-value'
            }
          });
        });
      });
    });
  });
});

describe('addDefaultNames', function() {
  var GLOBAL_CONFIG;
  GLOBAL_CONFIG = {
    registry: 'docker.example.tv'
  };
  it('preserves existing image name', function() {
    return expect(ServiceHelpers.addDefaultNames(GLOBAL_CONFIG, 'database', 'dev', {
      image: 'mysql'
    })).toEqual({
      containerName: 'database.dev',
      image: 'mysql',
      name: 'database'
    });
  });
  it('adds missing image name', function() {
    return expect(ServiceHelpers.addDefaultNames(GLOBAL_CONFIG, 'application', 'dev', {})).toEqual({
      containerName: 'application.dev',
      image: 'docker.example.tv/application',
      name: 'application'
    });
  });
  return it('tolerates no registry', function() {
    return expect(ServiceHelpers.addDefaultNames({}, 'application', 'dev', {})).toEqual({
      containerName: 'application.dev',
      image: 'application',
      name: 'application'
    });
  });
});

describe('listServicesWithEnvs', function() {
  return describe('envs', function() {
    var CONFIG;
    CONFIG = {
      service: {
        image: 'my-image',
        links: {
          'dev': ['service'],
          'dev.namespace': ['better-service'],
          'test': ['mock-service']
        },
        env: {
          'HOSTNAME': 'docker',
          'TEST_ONLY_VALUE': {
            'test': 'true'
          },
          'RAILS_ENV': {
            'dev': 'development',
            'test': 'test',
            'other': 'foo'
          }
        },
        ports: {
          'dev': ['3000']
        },
        volumesFrom: {
          'test': ['container']
        }
      },
      application: {
        image: 'application'
      }
    };
    return it('processes services', function() {
      return expect(ServiceHelpers.listServicesWithEnvs(CONFIG)).toEqual({
        'application': [],
        'service': ['dev', 'dev.namespace', 'test', 'other']
      });
    });
  });
});

describe('processConfig', function() {
  return describe('naming', function() {
    var CONFIG;
    CONFIG = {
      CONFIG: {
        registry: 'docker.example.tv'
      },
      'application': {},
      'database': {
        image: 'mysql'
      }
    };
    it('processes services', function() {
      return expect(ServiceHelpers.processConfig(CONFIG, 'dev', []).servicesConfig).toEqual({
        'application': {
          binds: [],
          command: null,
          containerName: 'application.dev',
          entrypoint: null,
          env: {},
          image: 'docker.example.tv/application',
          links: [],
          name: 'application',
          ports: [],
          restart: false,
          source: null,
          stateful: false,
          user: '',
          volumesFrom: []
        },
        'database': {
          binds: [],
          command: null,
          containerName: 'database.dev',
          env: {},
          entrypoint: null,
          image: 'mysql',
          links: [],
          name: 'database',
          ports: [],
          restart: false,
          source: null,
          stateful: false,
          user: '',
          volumesFrom: []
        }
      });
    });
    return it('returns global config', function() {
      return expect(ServiceHelpers.processConfig(CONFIG, 'dev', []).globalConfig).toEqual({
        registry: 'docker.example.tv'
      });
    });
  });
});
