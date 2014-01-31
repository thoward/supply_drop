namespace :puppet do

  namespace :bootstrap do
    desc "installs puppet via rubygems on an osx host"
    task :osx do
      on roles fetch(:puppet_roles) do
        if fetch(:use_sudo, true)
          sudo :gem, "install puppet --no-ri --no-rdoc"
        else
          execute :gem, "install puppet --no-ri --no-rdoc"
        end
      end
    end

    desc "installs puppet via apt on an ubuntu host"
    task :ubuntu do
      on roles fetch(:puppet_roles) do
        execute :mkdir, "-p #{fetch(:puppet_destination)}"
        sudo "apt-get update"
        sudo "apt-get install -y puppet rsync"
      end
    end

    desc "installs puppet via yum on a centos/redhat host"
    task :redhat do

      on roles fetch(:puppet_roles) do

        puppet_version = fetch(:puppet_version)
        if puppet_version == "latest"
          puppet_version = ""
        else
          puppet_version = "-#{puppet_version}" if not puppet_version.start_with? "-"
        end

        facter_version = fetch(:facter_version)
        if facter_version == "latest"
          facter_version = ""
        else
          facter_version = "-#{facter_version}" if not facter_version.start_with? "-"
        end
        info "installing versions; puppet: #{puppet_version} facter: #{facter_version}"        

        execute :mkdir, "-p #{fetch(:puppet_destination)}"

        sudo :rpm, "-i --quiet --replacepkgs http://yum.puppetlabs.com/el/6/products/$(arch)/puppetlabs-release-6-7.noarch.rpm"

        sudo :yum, "-y install rsync"
        sudo :yum, "-y --enablerepo=puppetlabs-products install puppet#{puppet_version} --noplugins"
        sudo :yum, "-y --disablerepo=* --enablerepo=puppetlabs-products install facter#{facter_version} --noplugins"

      end
    end

    desc "installs puppet via yum on an amazon linux host"
    task :amazon do

      on roles fetch(:puppet_roles) do

        puppet_version = fetch(:puppet_version)
        if puppet_version == "latest"
          puppet_version = ""
        else
          puppet_version = "-#{puppet_version}" if not puppet_version.start_with? "-"
        end

        facter_version = fetch(:facter_version)
        if facter_version == "latest"
          facter_version = ""
        else
          facter_version = "-#{facter_version}" if not facter_version.start_with? "-"
        end
        
        sudo :mkdir, "-p #{fetch(:puppet_destination)}"
        sudo :yum, "-y install rsync virt-what pciutils"

        sudo :rpm, "-i --quiet --replacepkgs http://yum.puppetlabs.com/el/6/products/$(arch)/puppetlabs-release-6-7.noarch.rpm"

        # installs the latest version of puppet from the puppetlabs yum repo
        # it's necessary to add --noplugins to disable the yum-priorities plugin
        # so that the newer versions of puppet can be installed from the puppetlabs repo
        # instead of being overridden by the epel version. Could also configure 
        # yum priorities, via editing /etc/yum.repos.d/epel.repo but this way 
        # doesn't require a conf file edit and functions equivalently
        sudo :yum, "-y --enablerepo=puppetlabs-products install puppet#{puppet_version} --noplugins"

        # currently, amazon's yum repo installs facter 1.6.18 which has 
        # incorrect reporting for amazon linux's os family causing many 
        # packages to fail to install. facter 1.7 fixes this, but needs 
        # a special repo install and manual dependency installs
        # if the amazon repo gets updated to 1.7, this will be obsolete 
        # and the puppet:bootstrap:redhat task can be used instead.
        sudo :yum, "-y --disablerepo=* --enablerepo=puppetlabs-products install facter#{facter_version}"
      end
    end

    namespace :puppetlabs do

      desc "setup the puppetlabs repo, then install via the normal method"
      task :ubuntu do
        on roles fetch(:puppet_roles) do
          execute :echo, :deb, "http://apt.puppetlabs.com/ $(lsb_release -sc) main | #{sudo} tee /etc/apt/sources.list.d/puppet.list"
          execute :echo, :deb, "http://apt.puppetlabs.com/ $(lsb_release -sc) dependencies | #{sudo} tee -a /etc/apt/sources.list.d/puppet.list"
          sudo "apt-key adv --keyserver keyserver.ubuntu.com --recv 4BD6EC30"
          puppet.bootstrap.ubuntu
        end
      end

      desc "setup the puppetlabs repo, then install via the normal method"
      task :redhat do
        info "PuppetLabs::RedHat bootstrap is not implemented yet"
      end
    end
  end

  desc "checks the syntax of all *.pp and *.erb files"
  task :syntax_check do
    run_locally do
      checker = SupplyDrop::SyntaxChecker.new(fetch(:puppet_source))
      info "Syntax Checking..."
      errors = false
      checker.validate_puppet_files.each do |file, err|
        debug "Puppet error: #{file}"
        debug err
        errors = true
      end
      checker.validate_templates.each do |file, err|
        debug "Template error: #{file}"
        debug err
        errors = true
      end
      raise "syntax errors" if errors
    end
  end

  desc "pushes the current puppet configuration to the server"
  task :update_code do
    on roles fetch(:puppet_roles), reject: lambda { |h| h.properties.nopuppet } do
      update_code
    end
  end

  desc "runs puppet with --noop flag to show changes"
  task :noop do
    on roles fetch(:puppet_roles) do #, reject: lambda { |h| h.properties.nopuppet } do
      begin
        lock
        prepare
        update_code
        puppet(:noop)
      ensure
        unlock
      end
    end
  end

  desc "an atomic way to noop and apply changes while maintaining a lock"
  task :noop_apply do
    on roles fetch(:puppet_roles), reject: lambda { |h| h.properties.nopuppet } do
      begin
        lock
        prepare
        update_code
        puppet(:noop)

        # note: ui.agree is gone in cap 3
        q = ":: Apply changes (y/n)?".to_sym
        ask(q, "no")
        puppet(:apply) if (fetch(q).strip.downcase[0] == ?y)
      ensure      
        unlock
      end
    end
  end

  desc "applies the current puppet config to the server"
  task :apply do
    on roles fetch(:puppet_roles), reject: lambda { |h| h.properties.nopuppet } do
      lock
      begin
        prepare
        update_code
        puppet(:apply)
      ensure
        unlock
      end
    end
  end

  desc "clears the puppet lockfile on the server."
  task :remove_lock do
    on roles fetch(:puppet_roles), reject: lambda { |h| h.properties.nopuppet } do
      warn "WARNING: puppet:remove_lock is deprecated, please use puppet:unlock instead"
      unlock
    end
  end

  desc "clears the puppet lockfile on the server."
  task :unlock do
    on roles fetch(:puppet_roles), reject: lambda { |h| h.properties.nopuppet } do
      unlock
    end
  end

  private

  def rsync
    SupplyDrop::Util.thread_pool_size = fetch(:puppet_parallel_rsync_pool_size)
    servers = SupplyDrop::Util.optionally_async(roles(:all), fetch(:puppet_parallel_rsync))
    overrides = {}
    overrides[:user] = fetch(:user, ENV['USER'])
    overrides[:port] = fetch(:port) if any?(:port)
    failed_servers = servers.map do |server|
      rsync_cmd = SupplyDrop::Rsync.command(
        fetch(:puppet_source),
        SupplyDrop::Rsync.remote_address(server.user || fetch(:user, ENV['USER']), server.hostname, fetch(:puppet_destination)),
        :delete => true,
        :excludes => fetch(:puppet_excludes),
        :ssh => (fetch(:ssh_options) || {}).merge(server.properties.ssh_options||{}).merge(overrides)
      )
      info rsync_cmd
      server.hostname unless system rsync_cmd
    end.compact

    raise "rsync failed on #{failed_servers.join(',')}" if failed_servers.any?
  end

  def update_code
    syntax_check if fetch(:puppet_syntax_check)
    rsync
  end

  def prepare
    execute :mkdir, "-p #{fetch(:puppet_destination)}"
    sudo :chown, "-R $USER: #{fetch(:puppet_destination)}"
  end

  def apply
    puppet(:apply)
  end

  def lock
    if should_lock?
      execute <<-CHECK_LOCK
if [ -f #{fetch(:puppet_lock_file)} ]; then stat -c "#{red_text("Puppet in progress, #{fetch(:puppet_lock_file)} owned by %U since %x")}" #{fetch(:puppet_lock_file)} >&2
exit 1
fi
echo 'ok'
exit 0
      CHECK_LOCK

      execute :touch, "#{fetch(:puppet_lock_file)}"
    end
  end

  def unlock
    sudo :rm, "-f #{fetch(:puppet_lock_file)}; true" if should_lock?
  end

  def should_lock?
    fetch(:puppet_lock_file) && !ENV['NO_PUPPET_LOCK']
  end

  def puppet(command = :noop)
    puppet_cmd = "#{fetch(:puppet_command)} --modulepath=#{fetch(:puppet_lib)} #{fetch(:puppet_parameters)}"
    flag = command == :noop ? '--noop' : ''

    within fetch(:puppet_destination) do
      as fetch(:puppet_runner) do
        begin
          sudo "#{puppet_cmd} #{flag}"
          info "Puppet #{command} complete."
        rescue
          error "Puppet #{command} failed."
        end
      end
    end
  end

  def red_text(text)
    "\033[0;31m#{text}\033[0m"
  end
end

namespace :load do
  task :defaults do
    set :puppet_roles, :all
    set :puppet_source, '.'
    set :puppet_destination, '/tmp/supply_drop'
    set :puppet_command, 'puppet apply'
    set :puppet_lib, lambda { "#{fetch(:puppet_destination)}/modules" }
    set :puppet_parameters, lambda { fetch(:puppet_verbose) ? '--debug --trace puppet.pp' : 'puppet.pp' }
    set :puppet_verbose, false
    set :puppet_excludes, %w(.git .svn)
    set :puppet_parallel_rsync, true
    set :puppet_parallel_rsync_pool_size, 10
    set :puppet_syntax_check, false
    set :puppet_runner, nil
    set :puppet_lock_file, '/tmp/puppet.lock'
    set :puppet_version, '2.7.23'
    set :facter_version, '1.7.4'
  end
end
