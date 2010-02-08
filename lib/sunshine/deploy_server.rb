require 'tmpdir'

module Sunshine

  ##
  # Keeps an SSH connection open to a server the app will be deployed to.
  # Deploy servers use the ssh command and support any ssh feature.
  # By default, deploy servers use the ControlMaster feature to share
  # socket connections, with the ControlPath = ~/.ssh/sunshine-%r%h:%p
  #
  # Deploy servers can be assigned any number of roles for classification.
  #
  # Setting session-persistant environment variables is supported by
  # accessing the @env attribute.

  class DeployServer < Console

    class ConnectionError < FatalDeployError; end

    LOGIN_LOOP = "echo ready; for (( ; ; )); do sleep 100; done"

    attr_reader :host, :user
    attr_accessor :roles, :ssh_flags, :rsync_flags


    ##
    # Deploy servers essentially need a user and a host. Typical instantiation
    # is done through either of these methods:
    #   DeployServer.new "user@host"
    #   DeployServer.new "host", :user => "user"
    #
    # The constructor also supports the following options:
    # :roles:: sym|array - roles assigned (web, db, app, etc...)
    # :env:: hash - hash of environment variables to set for the ssh session
    # :password:: string - password for ssh login; if missing the deploy server
    #                      will attempt to prompt the user for a password.

    def initialize host, options={}
      super $stdout, options

      @host, @user = host.split("@").reverse

      @user ||= options[:user]

      @roles = options[:roles] || []
      @roles = @roles.split(" ") if String === @roles
      @roles = [*@roles].compact.map{|r| r.to_sym }

      @rsync_flags = ["-azP"]
      @rsync_flags.concat [*options[:rsync_flags]] if options[:rsync_flags]

      @ssh_flags = [
        "-o ControlMaster=auto",
        "-o ControlPath=~/.ssh/sunshine-%r@%h:%p"
      ]
      @ssh_flags.concat ["-l", @user] if @user
      @ssh_flags.concat [*options[:ssh_flags]] if options[:ssh_flags]

      @pid, @inn, @out, @err = nil
    end


    ##
    # Runs a command via SSH. Optional block is passed the
    # stream(stderr, stdout) and string data

    def call command_str, options={}, &block
      Sunshine.logger.info @host, "Running: #{command_str}" do
        execute ssh_cmd(command_str, options), &block
      end
    end


    ##
    # Connect to host via SSH and return process pid

    def connect
      return @pid if connected?

      cmd = ssh_cmd LOGIN_LOOP, :sudo => false

      @pid, @inn, @out, @err = popen4(*cmd)
      @inn.sync = true

      data  = ""
      ready = @out.readline == "ready\n"

      unless ready
        disconnect
        raise ConnectionError, "Can't connect to #{@user}@#{@host}"
      end

      @inn.close
      @pid
    end


    ##
    # Check if SSH session is open and returns process pid

    def connected?
      Process.kill(0, @pid) && @pid rescue false
    end


    ##
    # Disconnect from host

    def disconnect
      return unless connected?

      kill_process @pid, "HUP"

      @inn.close rescue nil
      @out.close rescue nil
      @err.close rescue nil
      @pid = nil
    end


    ##
    # Download a file via rsync

    def download from_path, to_path, options={}, &block
      from_path = "#{@host}:#{from_path}"
      Sunshine.logger.info @host, "Downloading #{from_path} -> #{to_path}" do
        execute rsync_cmd(from_path, to_path, options), &block
      end
    end


    ##
    # Checks if the given file exists

    def file? filepath
      call("test -f #{filepath}") && true rescue false
    end


    ##
    # Create a file remotely

    def make_file filepath, content, options={}

      temp_filepath =
        "#{TMP_DIR}/#{File.basename(filepath)}_#{Time.now.to_i}#{rand(10000)}"

      File.open(temp_filepath, "w+"){|f| f.write(content)}

      self.upload temp_filepath, filepath, options

      File.delete(temp_filepath)
    end


    ##
    # Get the name of the OS

    def os_name
      @os_name ||= call("uname -s").strip.downcase
    end


    ##
    # Force symlinking a remote directory

    def symlink target, symlink_name
      call "ln -sfT #{target} #{symlink_name}" rescue false
    end


    ##
    # Uploads a file via rsync

    def upload from_path, to_path, options={}, &block
      to_path = "#{@host}:#{to_path}"
      Sunshine.logger.info @host, "Uploading #{from_path} -> #{to_path}" do
        execute rsync_cmd(from_path, to_path, options), &block
      end
    end


    private

    def build_rsync_flags options
      flags = @rsync_flags.dup

      rsync_sudo = sudo_cmd 'rsync', options

      unless rsync_sudo == 'rsync'
        flags << "--rsync-path='#{ rsync_sudo.join(" ") }'"
      end

      flags << "-e \"ssh #{@ssh_flags.join(' ')}\"" if @ssh_flags

      flags.concat [*options[:flags]] if options[:flags]

      flags
    end


    def rsync_cmd from_path, to_path, options={}
      cmd  = ["rsync", build_rsync_flags(options), from_path, to_path]
      cmd.flatten.compact.join(" ")
    end


    def ssh_cmd string, options={}
      cmd = sh_cmd string
      cmd = env_cmd cmd
      cmd = sudo_cmd cmd, options

      flags = [*options[:flags]].concat @ssh_flags

      ["ssh", flags, @host, cmd].flatten.compact
    end
  end
end
