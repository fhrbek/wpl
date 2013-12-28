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
class wpl(
  $backups              = false,
  $sendBackups          = false,
  $backupEmailFrom      = undef,
  $backupEmailPassword  = undef,
  $backupEmailRecipient = undef,
  ) {

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

  if($backups) {
    file { '/opt/wplbackup':
      ensure => directory,
      owner  => 'postgres',
      mode   => '0700',
    }

    if($sendBackups) {
      file { '/opt/gsender':
        ensure => directory,
        owner  => 'root',
        mode   => '0700',
      }

      file { '/opt/gsender/gsender':
        ensure  => present,
        source  => 'puppet:///modules/wpl/gsender/gsender',
        owner   => 'root',
        mode    => '0700',
        require => File['/opt/gsender'],
      }

      file { '/opt/gsender/lib':
        ensure => directory,
        owner  => 'root',
        mode   => '0700',
        require => File['/opt/gsender'],
      }

      file { '/opt/gsender/lib/gsender.jar':
        ensure  => present,
        source  => 'puppet:///modules/wpl/gsender/lib/gsender.jar',
        owner   => 'root',
        mode    => '0600',
        require => File['/opt/gsender/lib'],
      }

      file { '/opt/gsender/lib/args4j-2.0.21.jar':
        ensure  => present,
        source  => 'puppet:///modules/wpl/gsender/lib/args4j-2.0.21.jar',
        owner   => 'root',
        mode    => '0600',
        require => File['/opt/gsender/lib'],
      }

      file { '/opt/gsender/lib/mail-1.5.0-b01.jar':
        ensure  => present,
        source  => 'puppet:///modules/wpl/gsender/lib/mail-1.5.0-b01.jar',
        owner   => 'root',
        mode    => '0600',
        require => File['/opt/gsender/lib'],
      }

      file { '/opt/wplbackup.cron':
        ensure  => present,
        owner   => 'root',
        mode    => '0700', 
        content => "TIMESTAMP=`date +%Y%m%d%H%M%S`; cd /opt/gsender; su - postgres -c \"pg_dump -f /opt/wplbackup/\$TIMESTAMP.sql.gz -Z 9 wittmannpokerleague\";./gsender -f \"${backupEmailFrom}\" -s \"WPL Backup \$TIMESTAMP\" -p \"${backupEmailPassword}\" -b \"This is a WPL database backup file.\" -a /opt/wplbackup/\$TIMESTAMP.sql.gz \"${backupEmailRecipient}\";TIMESTAMP=",
      }
    }
    else {
      file { '/opt/wplbackup.cron':
        ensure  => present,
        owner   => 'root',
        mode    => '0700', 
        content => "TIMESTAMP=`date +%Y%m%d%H%M%S`; su - postgres -c \"pg_dump -f /opt/wplbackup/\$TIMESTAMP.sql.gz -Z 9 wittmannpokerleague\";TIMESTAMP=",
      }
    }

    cron { 'wplbackup':
      command => '/opt/wplbackup.cron',
      user    => 'root',
      hour    => 5,
      minute  => 0,
      require => File['/opt/gsender'],
    }
  }
  else {
    file { '/opt/wplbackup.cron':
      ensure => absent,
    }

    cron { 'wplbackup':
      ensure => absent,
    }
  }
}
