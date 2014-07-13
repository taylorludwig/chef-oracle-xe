oracle_filename = node[:oracle_xe][:oracle_install_filename]
symlinks = {
  '/sbin/insserv' => '/usr/lib/insserv/insserv',
  '/bin/awk' => '/usr/bin/awk'
}

execute 'copy oracle installation file' do
  command "cp #{node[:oracle_xe][:oracle_install_source]}/#{oracle_filename} /tmp/"
  creates "/tmp/#{oracle_filename}"
end

%w{alien bc libaio1 expect unixodbc chkconfig pmount}.each do | pkg |
  package pkg do
    action :install
  end
end

template '/tmp/oracle_xe.rsp' do
  source 'oracle_xe.rsp.erb'
  mode 600
  variables :http_port => node[:oracle_xe][:http_port], :listener_port => node[:oracle_xe][:listener_port], :sysdba_password => node[:oracle_xe][:sysdba_password]
end

group 'dba'

user 'oracle' do
  comment 'user for managing databases'
  gid 'dba'
  shell '/bin/bash'
  home '/home/oracle'
  supports :manage_home => true
end

symlinks.each do |to, from|
  execute "symlink from #{from} to #{to}" do
    command "ln -s #{from} #{to}"
    creates to
  end
end

execute 'create subsys' do
  command 'mkdir /var/lock/subsys'
  creates '/var/lock/subsys'
end

cookbook_file '/etc/sysctl.d/60-oracle.conf' do
  action :create
  source 'oracle.conf'
  mode 644
end

execute 'backup chkconfig if exists' do
  command 'mv /sbin/chkconfig /sbin/chkconfig.bak'
  creates '/sbin/chkconfig.bak'
  only_if "test -f /sbin/chkconfig"
end

cookbook_file '/sbin/chkconfig' do
  action :create
  source 'chkconfig'
  mode 755
end

execute 'install oracle' do
  user 'root'
  command "alien --scripts -i #{oracle_filename}"
  cwd '/tmp'
  action :run
  creates '/u01/app/oracle'
end

execute 'restore chkconfig from backup' do
  command 'mv -f /sbin/chkconfig.bak /sbin/chkconfig'
  only_if "test -f /sbin/chkconfig.bak"
end

service "oracle-xe" do
  action :nothing
  supports :status => true, :start => true, :stop => true, :restart => true
end

bash 'fix /dev/shm problem' do
  code %Q{
    umount /dev/shm
    rm /dev/shm -rf
    mkdir /dev/shm
    mount -t tmpfs shmfs -o size=2048m /dev/shm
    sysctl kernel.shmmax=1073741824
    touch /dev/shm/.shmfix
  }
  not_if { ::File.exists?('/dev/shm/.shmfix') }
  notifies :restart, "service[oracle-xe]"
end

bash 'setup oracle user' do
  user 'oracle'
  cwd '/home/oracle'
  code %Q{
    echo "" >>./.profile
    touch ./.user_created
  }
  creates '/home/oracle/.user_created'
end

bash 'environment variables for oracle' do
  user "root"
  code <<-EOH
    echo '. /u01/app/oracle/product/11.2.0/xe/bin/oracle_env.sh' >> /etc/profile
    source /u01/app/oracle/product/11.2.0/xe/bin/oracle_env.sh
    touch /home/oracle/.oracle_environment_vars
  EOH
  action :run
  creates '/home/oracle/.oracle_environment_vars'
end

execute 'configure_oracle' do
  command '/etc/init.d/oracle-xe configure responseFile=/tmp/oracle_xe.rsp && touch /home/oracle/.oracle_configured'
  action :run
  creates '/home/oracle/.oracle_configured'
end

