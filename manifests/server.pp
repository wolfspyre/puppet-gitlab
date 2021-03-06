# Class:: gitlab::server
#
#
class gitlab::server(
  $git_email          = $gitlab::git_email,
  $git_home           = $gitlab::git_home,
  $git_user           = $gitlab::git_user,
  $gitlab_branch      = $gitlab::gitlab_branch,
  $gitlab_dbhost      = $gitlab::gitlab_dbhost,
  $gitlab_dbname      = $gitlab::gitlab_dbname,
  $gitlab_dbport      = $gitlab::gitlab_dbport,
  $gitlab_dbpwd       = $gitlab::gitlab_dbpwd,
  $gitlab_dbtype      = $gitlab::gitlab_dbtype,
  $gitlab_dbuser      = $gitlab::gitlab_dbuser,
  $gitlab_domain      = $gitlab::gitlab_domain,
  $gitlab_repodir     = $gitlab::gitlab_repodir,
  $gitlab_sources     = $gitlab::gitlab_sources,
  $nginx_service_name = $gitlab::nginx_service_name,
  $nginx_group        = $gitlab::nginx_group,
  $ldap_base          = $gitlab::ldap_base,
  $ldap_bind_dn       = $gitlab::ldap_bind_dn,
  $ldap_bind_password = $gitlab::ldap_bind_password,
  $ldap_enabled       = $gitlab::ldap_enabled,
  $ldap_host          = $gitlab::ldap_host,
  $ldap_method        = $gitlab::ldap_method,
  $ldap_port          = $gitlab::ldap_port,
  $ldap_uid           = $gitlab::ldap_uid,
  ) {
  #deps
  include gitlab
  require gitlab::gitlabshell
  
  #Ordering
  package {
    'bundler':
      ensure   => installed,
      provider => gem;
    'charlock_holmes':
      ensure   => '0.6.9.4',
      provider => gem;
  }

  $gitlab_without_gems = $gitlab_dbtype ? {
    mysql    => 'postgres',
    pgsql    => 'mysql',
    default  => '',
  }

  #needed, at least on rh/cent to permit the init script to run
  augeas {'gitlab_nuke_requiretty':
    context => '/files/etc/sudoers',
    changes => ['set Defaults[type=":root"]/type :root', 'set Defaults[type=":root"]/requiretty/negate ""'],
  }

  Exec{
    path => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
    logoutput   => 'on_failure',
  }
  exec {
    'Get gitlab':
      command     => "git clone -b ${gitlab_branch} ${gitlab_sources} ./gitlab",
      creates     => "${git_home}/gitlab",
      cwd         => $git_home,
      user        => $git_user;
    'Install gitlab':
      command  => "bundle install --without development test ${gitlab_without_gems} --deployment",
      provider => 'shell',
      cwd      => "${git_home}/gitlab",
      user     => $git_user,
      unless   => "/usr/bin/test -f ${git_home}/.gitlab_setup_done",
      timeout  => 0,
      require  => [
        Exec['Get gitlab'],
        Package['bundler']
      ];
    # FIXME sudo ln -s /usr/bin/python /usr/bin/python2
    # recommanded by gitlab (bundle exec rake gitlab:check RAILS_ENV=production)
    # but it's a bit ugly...
    'Setup gitlab DB':
      command     => '/usr/bin/yes yes | bundle exec rake gitlab:setup RAILS_ENV=production',
      provider    => 'shell',
      cwd         => "${git_home}/gitlab",
      user        => $git_user,
      creates     => "${git_home}/.gitlab_setup_done",
      require     => [
        Exec['Install gitlab'],
        File["${git_home}/gitlab/config/database.yml"],
        File["${git_home}/gitlab/tmp"],
        Sshkey['localhost'],
        Package['bundler']
        ],
      refreshonly => true;
  }

  file {
    "${git_home}/.gitlab_setup_done":
      ensure  => 'present',
      owner   => 'root',
      group   => 'root',
      require => Exec['Setup gitlab DB'];
  }

  # fixing eventmachine and thin gem build problems
  # on newer debian/ubuntu versions
  if ($::osfamily == 'Debian'){
    file {
      "${git_home}/gitlab/.bundle":
        ensure  => directory,
        owner   => $git_user,
        group   => $git_user,
        require => Exec['Get gitlab'],
        before  => File['bundle_config'];
      'bundle_config':
        path    => "${git_home}/gitlab/.bundle/config",
        content => template('gitlab/gitlab.bundle.config.erb'),
        replace => false,
        owner   => $git_user,
        group   => $git_user,
        before  => Exec['Install gitlab']; }
  }

  file {
    "${git_home}/gitlab/config/database.yml":
      ensure  => file,
      content => template('gitlab/database.yml.erb'),
      owner   => $git_user,
      group   => $git_user,
      require => [Exec['Get gitlab'],
                  File["${git_home}/gitlab/config/gitlab.yml"]];
    "${git_home}/gitlab/config/puma.rb":
      ensure  => file,
      content => template('gitlab/puma.rb.erb'),
      owner   => $git_user,
      group   => $git_user,
      require => [Exec['Get gitlab'],
                  File["${git_home}/gitlab/config/gitlab.yml"]];
    "${git_home}/gitlab/config/gitlab.yml":
      ensure  => file,
      content => template('gitlab/gitlab.yml.erb'),
      owner   => $git_user,
      group   => $git_user,
      mode    => '0640',
      require => Exec['Get gitlab'],
      notify  => Exec['Setup gitlab DB'];
    ["${git_home}/gitlab/tmp",
      "${git_home}/gitlab/log",
      "${git_home}/gitlab-satellites",
      "${git_home}/gitlab/public"]:
      ensure  => directory,
      mode    => '0755',
      owner   => $git_user,
      group   => $git_user,
      require => Exec['Get gitlab'];
    "${git_home}/gitlab/public/uploads":
      ensure  => directory,
      mode    => '0755',
      owner   => $git_user,
      group   => $git_user,
      require => File["${git_home}/gitlab/public"];
    ["${git_home}/gitlab/tmp/pids","${git_home}/gitlab/tmp/sockets"]:
      ensure    => directory,
      mode      => '0755',
      owner     => $git_user,
      group     => $git_user,
      require   => File["${git_home}/gitlab/tmp"];
    "${git_home}/.gitconfig":
      content => template('gitlab/git.gitconfig.erb'),
      mode    => '0644';
  }

  sshkey {
    'localhost':
      ensure       => present,
      host_aliases => $::fqdn,
      key          => $::sshrsakey,
      type         => 'ssh-rsa'
  }

  file {
    '/var/lib/gitlab':
      ensure => directory,
      owner  => $git_user,
      group  => $nginx_group,
      mode   => '0775';
  }

  file {
    '/etc/init.d/gitlab':
      ensure  => file,
      content => template('gitlab/etc/init.d/gitlab.erb'),
      owner   => root,
      group   => root,
      mode    => '0755',
      notify  => Service['gitlab'],
      require => Exec['Setup gitlab DB'];
  }

  service {
    'gitlab':
      ensure     => running,
      enable     => true,
      hasrestart => true,
      pattern    => 'puma',
      require    => [Augeas['gitlab_nuke_requiretty'],File['/etc/init.d/gitlab',"${git_home}/gitlab/tmp/pids","${git_home}/gitlab/tmp/sockets"]];
  }
  file {
    '/etc/nginx/conf.d/gitlab.conf':
      ensure  => file,
      content => template('gitlab/nginx-gitlab.conf.erb'),
      owner   => root,
      group   => root,
      mode    => '0644',
      notify  => Service[$nginx_service_name];
  }

} # Class:: gitlab::server

