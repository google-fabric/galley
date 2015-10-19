# You can test this Galleyfile locally w/ galley commands! There's a bit of a trick to getting
# galley to resolve correctly.
#
# In the directory above this, run:
#  $ npm link; npm link galley
#
# This will make it so that galley-cli run in this directory will recur up to find galley's own
# package.json, and from there be able to resolve 'galley'.

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
