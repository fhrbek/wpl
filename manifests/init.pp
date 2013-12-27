# == Class: wpl
#
# This class installs the Wittmann Poker League application
#
# === Parameters
#
# No parameters are required
#
# === Variables
#
# No variables are required
#
# === Examples
#
#  class { 'wpl':
#  }
#
# === Authors
#
# Filip Hrbek <filip.hrbek@gmail.com>
#
# === Copyright
#
# Copyright 2013 Filip Hrbek
#
class wpl {

  # Install Apache Tomcat server
  include tomcat6

  file { "${tomcat6::params::catalina_home['CATALINA_HOME']}/conf/server.xml":
    source => 'puppet:///modules/wpl/server.xml',
    seltype => 'etc_t',
    notify => Service['tomcat6'],
  }

  # Install Apache HTTP server
  class { 'apache':
    default_vhost => false,
    purge_configs => false,
    require => Class['tomcat6'],
  }

  apache::vhost { 'wpl':
    ip => '*',
    port => 80,
    servername => 'localhost',
    docroot => '/var/www/html',
    proxy_pass => [
      { 'path' => '/', 'url' => 'ajp://localhost:8008/' },
    ],
  }

  apache::mod { 'proxy_ajp': }

  include postgresql::server

  postgresql::server::db { 'wittmannpokerleague':
    user     => 'wpldata',
    password => 'md5ac5ed10a8c235ed8737bb3dcc4968fe3',
    encoding => 'utf8',
  }

  package { 'curl':
    ensure => installed,
  }

  cron { 'wplmail':
    command => "curl -G http://localhost/cron/invitations",
    user    => 'root',
    hour    => 4,
    minute  => 0,
  }
}
