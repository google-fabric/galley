module.exports =
  CONFIG:
    rsync:
      image: 'galley-integration-rsync'
      module: 'root'
      suffix: 'galley-integration-rsync'

  ADDONS:
    'backend-addon':
      'application':
        links:
          'galley-integration': ['backend']

  'application':
    image: 'galley-integration-application'
    source: '/src'

  'backend':
    image: 'galley-integration-backend'
    links:
      'galley-integration': ['database']
    source: '/src/public'
    volumesFrom: ['config']

  'config':
    image: 'galley-integration-config'

  'database':
    image: 'galley-integration-database'
    stateful: true
