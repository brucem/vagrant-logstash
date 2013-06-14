Exec { 
  path    => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/opt/vagrant_ruby/bin',
  timeout => 0,
}

node base {
  group { 'puppet': ensure => 'present' }

  # Install NTP to keep the system time correct
  class { 'ntp':
    ensure => 'running',
  }

  # Postfix to provide a local mail system
  #package { 'postfix':
  #  ensure => 'present',
  #}

  # Enable unattended upgrades so that security related updates are installed
  # automatically
  #  package {'unattended-upgrades':
  #  ensure => 'present'
  #}

}

node default inherits base {

  package { 'curl':
    ensure => present,
  }

  class{ 'git': }
  class{ 'java': }

  $ls_jarbase     = 'https://logstash.objects.dreamhost.com/release'
  $ls_jarfile     = 'logstash-1.1.12-flatjar.jar'
  $ls_jarpath     = "/tmp/$ls_jarfile"
  $ls_installpath = '/opt/logstash'

  file { $ls_installpath:
    ensure => directory,
    owner  => root,
    group  => root,
    mode   => '0755',
  }
 
  exec { 'get-ls-jarfile':
    command => "/usr/bin/curl -L ${ls_jarbase}/${ls_jarfile} -o ${ls_jarpath}",
    creates => $ls_jarpath,
    require => Package['curl'],
  }

  class { 'logstash':
    jarfile     => $ls_jarpath,
    provider    => 'custom',
    installpath => $ls_installpath,
    instances   => [ 'indexer', 'shipper' ],
    require     => [Exec['get-ls-jarfile'], Class['java'], File[$ls_installpath]],
  }

  $es_base     = 'https://download.elasticsearch.org/elasticsearch/elasticsearch/'
  $es_package  = 'elasticsearch-0.20.5.deb'
  $es_path     = "/tmp/$es_package"

  exec { 'get-es-package':
    command => "/usr/bin/curl -L ${es_base}/${es_package} -o ${es_path}",
    creates => $es_path,
    require => Package['curl'],
  }

  class { 'elasticsearch': 
    pkg_source       => $es_path,
    config           => {
      'node.name'    => 'elasticsearch001',
      'cluster.name' => 'logstash'
    },
    require           => [Exec['get-es-package'],Class['java']],
  }

  $es_ls_template_base = 'http://www.logstashbook.com/code/3/'
  $es_ls_template_file = 'elasticsearch_mapping.json'
  $es_ls_template_path = "/tmp/$es_ls_template_file"

  exec {'get-es-ls-template':
    command => "/usr/bin/curl -L ${es_ls_template_base}/${es_ls_template_file} -o ${es_ls_template_path}",
    creates => $es_ls_template_path,
    require => Package['curl'],
  }
     
  elasticsearch::template { logstash_per_index:
    file    => $es_ls_template_path,
    require => [Exec['get-es-ls-template'],Class['elasticsearch']],
  }

  class { 'redis': }

  # Setup the LS indexer
  logstash::input::redis { indexer-redis-input:
    type      => 'redis-input',
    data_type => 'list',
    host      => 'localhost',
    key       => 'logstash',
    instances => [ 'indexer' ]
  }

  logstash::output::elasticsearch { indexer-elasticsearch-output:
    cluster   => 'logstash',
    instances => [ 'indexer' ]
  }

  # Setup the LS shipper
  logstash::output::redis { shipper-redis-output:
    host      => ['localhost'],
    data_type => 'list',
    key       => 'logstash',
    instances => [ 'shipper' ],
  }

  logstash::input::file { shipper-file-input:
    type    => 'syslog',
    path    => ['/var/log/auth.log', '/var/log/syslog'],
    exclude => ["*.gz", "shipper.log"],
    instances => [ 'shipper' ],
  }


  class {'kibana3': }

}
