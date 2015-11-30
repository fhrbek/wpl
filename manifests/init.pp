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

  include postgresql::server

  postgresql::server::db { 'wittmannpokerleague':
    user     => 'wpldata',
    password => 'md5ac5ed10a8c235ed8737bb3dcc4968fe3',
    encoding => 'utf8',
  }

  package { 'wget':
    ensure => installed,
  }

  $staging_dir = '/opt/staging'
  $staging_file = "$staging_dir/latest.backup"

  file { $staging_dir:
    ensure => directory,
  }

  exec { 'load_db':
    path => '/bin:/usr/bin',
    command => "wget https://github.com/fhrbek/wpl-staging/raw/master/latest.backup -O $staging_file;su - postgres -c \"pg_restore -d wittmannpokerleague $staging_file -e\"",
    onlyif => 'su - postgres -c "psql wittmannpokerleague -c \'\\d\' -qt"|wc -w|grep \'^0$\'',
    require => [Postgresql::Server::Db['wittmannpokerleague'], Package['wget'], File[$staging_dir]],
  }

  $catalina_base = '/usr/share/tomcat'

  # Install Java
  class { 'java': }->

  # Install Apache Tomcat server from EPEL
  class { 'tomcat':
    install_from_source => false,
  }->
  class { 'epel': }->
  tomcat::instance{ 'default':
      package_name => 'tomcat',
  }->

  # Disable default HTTP connector
  tomcat::config::server::connector { 'tomcat-http':
    catalina_base => $catalina_base,
    connector_ensure => absent,
    protocol => 'HTTP/1.1',
    notify => Tomcat::Service['default'],
  }->

  # Enable AJP connector
  tomcat::config::server::connector { 'tomcat-ajp':
    catalina_base => $catalina_base,
    protocol => 'AJP/1.3',
    port => '8008',
    additional_attributes => {
      'redirectPort' => '8080'
    },
    notify => Tomcat::Service['default'],
  }->

  # Start Apache Tomcat service
  tomcat::service { 'default':
    use_jsvc     => false,
    use_init     => true,
    service_name => 'tomcat',
  }->

  tomcat::war { 'wpl':
    catalina_base => $catalina_base,
    war_name => 'ROOT.war',
    war_source => 'https://github.com/fhrbek/wpl-staging/raw/master/wpl.war',
    require => Exec['load_db']
  }

  # Install Apache HTTP server
  class { 'apache':
    default_vhost => false,
    purge_configs => false,
    mpm_module    => false,
    require       => Tomcat::Service['default'],
  }

  # Minimize resources for Apache HTTP server
  class { 'apache::mod::prefork':
    startservers    => '1',
    minspareservers => '1',
    maxspareservers => '1',
  }

  apache::vhost { '_default_':
    ip         => '*',
    port       => 80,
    servername => 'localhost',
    docroot    => '/var/www/html',
    proxy_pass => [
      { 'path' => '/', 'url' => 'ajp://localhost:8008/' },
    ],
  }

  apache::mod { 'proxy_ajp': }

  package { 'curl':
    ensure => installed,
  }

  cron { 'wplmail':
    command => "curl -sSG http://localhost/cron/invitations",
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
