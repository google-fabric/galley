expect = require 'expect'
_ = require 'lodash'

ServiceHelpers = require '../lib/lib/service_helpers'

describe 'normalizeAddonArgs', ->
  describe 'with a non-delimited string', ->
    it 'should be an array with one value', ->
      expect(ServiceHelpers.normalizeAddonArgs('beta')).toEqual ['beta']

  describe 'with a delimited string with two values', ->
    it 'should be an array with two values', ->
      expect(ServiceHelpers.normalizeAddonArgs('beta,other')).toEqual ['beta', 'other']  

  describe 'with a delimited string with a bad leading comma', ->
    it 'should be an array with one value', ->
      expect(ServiceHelpers.normalizeAddonArgs(',other')).toEqual ['other']

  describe 'with a delimited string with a bad trailing comma', ->
    it 'should be an array with one value', ->
      expect(ServiceHelpers.normalizeAddonArgs('beta,')).toEqual ['beta']

  describe 'with an array with one value', ->
    it 'should be an array with one value', ->
      expect(ServiceHelpers.normalizeAddonArgs(['beta'])).toEqual ['beta']

  describe 'with an array with one value', ->
    it 'should be an array with one value', ->
      expect(ServiceHelpers.normalizeAddonArgs(['beta'])).toEqual ['beta']

  describe 'with an array with two values', ->
    it 'should be an array with two values', ->
      expect(ServiceHelpers.normalizeAddonArgs(['beta', 'other'])).toEqual ['beta', 'other']

  describe 'with an array with two values, one of which is delimited', ->
    it 'should be an array with three values', ->
      expect(ServiceHelpers.normalizeAddonArgs(['beta', 'other,third'])).toEqual ['beta', 'other', 'third']

describe 'normalizeVolumeArgs', ->
  it 'handles a single value', ->
    expect(ServiceHelpers.normalizeVolumeArgs '/host:/container').toEqual ['/host:/container']
  it 'handles multiple values', ->
    volumes = ['/host1:/container1', '/host2:/container2']
    expect(ServiceHelpers.normalizeVolumeArgs volumes).toEqual volumes
  it 'resolves relative paths', ->
    expect(ServiceHelpers.normalizeVolumeArgs ['host:/container']).toEqual [
      "#{process.cwd()}/host:/container"
    ]

describe 'generatePrereqServices', ->
  describe 'generates simple dependency chain', ->
    config =
      service:
        links: ['service_two']
        volumesFrom: []
      service_two:
        links: ['service_three']
        volumesFrom: []
      service_three:
        links: ['service_four']
        volumesFrom: ['service_five']
      service_four:
        links: []
        volumesFrom: []
      service_five:
        links: []
        volumesFrom: []
    it 'should generate correctly ordered list', ->
      expect(ServiceHelpers.generatePrereqServices 'service', config).toEqual ['service_five', 'service_four', 'service_three', 'service_two', 'service']

  describe 'does not have duplicate service entries, keeps the earliest', ->
    config =
      service:
        links: ['service_two']
        volumesFrom: []
      service_two:
        links: ['service_three', 'service_four']
        volumesFrom: []
      service_three:
        links: ['service_four']
        volumesFrom: []
      service_four:
        links: []
        volumesFrom: []
    it 'should generate correctly ordered list', ->
      expect(ServiceHelpers.generatePrereqServices 'service', config).toEqual ['service_four', 'service_three', 'service_two', 'service']

  describe 'fails on circular dependency', ->
    config =
      service:
        links: ['service_another']
      service_another:
        links: ['service']
    it 'should throw', ->
      expect( -> ServiceHelpers.generatePrereqServices('service', config)).toThrow('Circular dependency for service: service -> service_another -> service')

describe 'collapseEnvironment', ->
  describe 'not parameterized', ->
    CONFIG_STRING_VALUE = 'foo'
    CONFIG_ARRAY_VALUE = ['foo', 'bar']

    it 'does not modify a string', ->
      expect(ServiceHelpers.collapseEnvironment CONFIG_STRING_VALUE, 'dev').toEqual CONFIG_STRING_VALUE

    it 'does not modify an array', ->
      expect(ServiceHelpers.collapseEnvironment CONFIG_ARRAY_VALUE, 'dev').toEqual CONFIG_ARRAY_VALUE

  describe 'parameterized', ->
    CONFIG_VALUE =
      'dev': 'foo'
      'test': 'bar'
      'test.cucumber': 'baz'

    it 'returns defaultValue when env is missing', ->
      expect(ServiceHelpers.collapseEnvironment CONFIG_VALUE, 'prod', ['default']).toEqual ['default']

    it 'finds named environment', ->
      expect(ServiceHelpers.collapseEnvironment CONFIG_VALUE, 'dev', null).toEqual 'foo'

    it 'finds namespaced environment', ->
      expect(ServiceHelpers.collapseEnvironment CONFIG_VALUE, 'test.cucumber', null).toEqual 'baz'

    it 'falls back when namespace is missing', ->
      expect(ServiceHelpers.collapseEnvironment CONFIG_VALUE, 'dev.cucumber', null).toEqual 'foo'

describe 'collapseServiceConfigEnv', ->
  describe 'array parameterization', ->
    CONFIG =
      image: 'my-image'
      links:
        'dev': ['service']
        'dev.namespace': ['better-service']
        'test': ['mock-service']
      ports:
        'dev': ['3000']
      volumesFrom:
        'test': ['container']

    it 'collapses down to just the environment', ->
      expect(ServiceHelpers.collapseServiceConfigEnv(CONFIG, 'dev.namespace', [])).toEqual
        image: 'my-image'
        links: ['better-service']
        ports: ['3000']
        volumesFrom: []

  describe 'env parameterization', ->
    CONFIG =
      env:
        'HOSTNAME': 'docker'
        'TEST_ONLY_VALUE':
          'test': 'true'
        'RAILS_ENV':
          'dev': 'development'
          'test': 'test'

    it 'paramerizes the env variables', ->
      expect(ServiceHelpers.collapseServiceConfigEnv(CONFIG, 'dev.namespace', [])).toEqual
        env:
          'HOSTNAME': 'docker'
          'TEST_ONLY_VALUE': null
          'RAILS_ENV': 'development'

  describe 'addons', ->
    describe 'array parameter merging', ->
      EXPECTED =
        links: ['database', 'addon-service']

      describe 'without env', ->
        CONFIG = 
          addons:
            'my-addon':
              links: ['addon-service']
          links: ['database']

        it 'merges addons array parameters', ->
          expect(ServiceHelpers.collapseServiceConfigEnv(CONFIG, 'unused', ['my-addon'])).toEqual EXPECTED

      describe 'with addon env', ->
        CONFIG = 
          addons:
            'my-addon':
              links:
                'dev': ['addon-service']
          links: ['database']

        it 'merges addons array parameters', ->
          expect(ServiceHelpers.collapseServiceConfigEnv(CONFIG, 'dev', ['my-addon'])).toEqual EXPECTED

      describe 'with base env', ->
        CONFIG = 
          addons:
            'my-addon':
              links: ['addon-service']
          links:
            'dev': ['database']

        it 'merges addons array parameters', ->
          expect(ServiceHelpers.collapseServiceConfigEnv(CONFIG, 'dev', ['my-addon'])).toEqual EXPECTED

      describe 'with addon namespaced env', ->
        CONFIG = 
          addons:
            'my-addon':
              links:
                'dev.namespace': ['addon-service']
          links:
            'dev': ['database']

        it 'merges addons array parameters', ->
          expect(ServiceHelpers.collapseServiceConfigEnv(CONFIG, 'dev.namespace', ['my-addon'])).toEqual EXPECTED

    describe 'env parameter merging', ->
      describe 'with no base env', ->
        CONFIG =
          addons:
            'my-addon':
              env:
                'HOSTNAME': 'docker-addon'
                'CUSTOM':
                  'dev.namespace': 'custom-value'

        it 'paramerizes the env variables', ->
          expect(ServiceHelpers.collapseServiceConfigEnv(CONFIG, 'dev.namespace', ['my-addon'])).toEqual
            env:
              'HOSTNAME': 'docker-addon'
              'CUSTOM': 'custom-value'

      describe 'with a base env', ->  
        CONFIG =
          env:
            'HOSTNAME': 'docker'
            'TEST_ONLY_VALUE':
              'test': 'true'
            'RAILS_ENV':
              'dev': 'development'
              'test': 'test'
          addons:
            'my-addon':
              env:
                'HOSTNAME': 'docker-addon'
                'CUSTOM':
                  'dev.namespace': 'custom-value'

        it 'paramerizes the env variables', ->
          expect(ServiceHelpers.collapseServiceConfigEnv(CONFIG, 'dev.namespace', ['my-addon'])).toEqual
            env:
              'HOSTNAME': 'docker-addon'
              'TEST_ONLY_VALUE': null
              'RAILS_ENV': 'development'
              'CUSTOM': 'custom-value'

      describe 'with multiple addons', ->
        CONFIG =
          env:
            'HOSTNAME': 'docker'
            'TEST_ONLY_VALUE':
              'test': 'true'
            'RAILS_ENV':
              'dev': 'development'
              'test': 'test'
          addons:
            'my-addon':
              env:
                'HOSTNAME': 'docker-addon'
            'my-second-addon':
              env:
                'CUSTOM':
                  'dev.namespace': 'custom-value'

        it 'paramerizes the env variables', ->
          expect(ServiceHelpers.collapseServiceConfigEnv(CONFIG, 'dev.namespace', ['my-addon', 'my-second-addon'])).toEqual
            env:
              'HOSTNAME': 'docker-addon'
              'TEST_ONLY_VALUE': null
              'RAILS_ENV': 'development'
              'CUSTOM': 'custom-value'

describe 'addDefaultNames', ->
  GLOBAL_CONFIG = registry: 'docker.example.tv'

  it 'preserves existing image name', ->
    expect(ServiceHelpers.addDefaultNames(GLOBAL_CONFIG, 'database', 'dev', {image: 'mysql'})).toEqual
      containerName: 'database.dev'
      image: 'mysql'

  it 'adds missing image name', ->
    expect(ServiceHelpers.addDefaultNames(GLOBAL_CONFIG, 'application', 'dev', {})).toEqual
      containerName: 'application.dev'
      image: 'docker.example.tv/application'

  it 'tolerates no registry', ->
    expect(ServiceHelpers.addDefaultNames({}, 'application', 'dev', {})).toEqual
      containerName: 'application.dev'
      image: 'application'

describe 'processConfig', ->
  describe 'naming', ->
    CONFIG =
      CONFIG:
        registry: 'docker.example.tv'
      'application': {}
      'database':
        image: 'mysql'

    it 'processes services', ->
      expect(ServiceHelpers.processConfig(CONFIG, 'dev', []).servicesConfig).toEqual
        'application':
          binds: []
          command: null
          containerName: 'application.dev'
          entrypoint: null
          env: {}
          image: 'docker.example.tv/application'
          links: []
          ports: []
          source: null
          stateful: false
          volumesFrom: []
        'database':
          binds: []
          command: null
          containerName: 'database.dev'
          env: {}
          entrypoint: null
          image: 'mysql'
          links: []
          ports: []
          source: null
          stateful: false
          volumesFrom: []

    it 'returns global config', ->
      expect(ServiceHelpers.processConfig(CONFIG, 'dev', []).globalConfig).toEqual
        registry: 'docker.example.tv'
