module Sunshine

  ##
  # The Console class handles local input, output and execution to the shell.

  class Console

    include Open4

    LOCAL_USER = `whoami`.chomp
    LOCAL_HOST = `hostname`.chomp

    SUDO_PROMPT = /^Password:/

    attr_reader :user, :host, :password, :input, :output
    attr_accessor :env, :sudo

    def initialize output = $stdout, options={}
      @output = output
      @input = HighLine.new

      @user = LOCAL_USER
      @host = LOCAL_HOST

      @sudo     = options[:sudo]
      @env      = options[:env] || {}
      @password = options[:password]
    end


    ##
    # Checks for equality

    def == console
      @host == console.host && @user == console.user
    end


    ##
    # Prompt the user for input.

    def ask(*args, &block)
      @input.ask(*args, &block)
    end


    ##
    # Execute a command on the local system and return the output.

    def call cmd, options={}, &block
      sudo_val = @sudo
      sudo_val = options[:sudo] if options.has_key?(:sudo)
      cmd      = sudo_cmd(cmd, sudo_val) if sudo_val

      execute cmd, &block
    end


    ##
    # Close the output IO. (Required by the Logger class)

    def close
      @output.close
    end


    ##
    # Prompt the user for a password

    def prompt_for_password
      @password = ask("#{@user}@#{@host} Password:") do |q|
        q.echo = false
      end
    end


    ##
    # Build an env command if an env_hash is passed

    def env_cmd cmd, env_hash=@env
      if env_hash && !env_hash.empty?
        env_vars = env_hash.map{|e| e.join("=")}
        cmd = ["env", env_vars, cmd]
      end
      cmd
    end


    ##
    # Build an sh -c command

    def sh_cmd string
      string = string.gsub(/'/){|s| "'\\''"}

      ["sh", "-c", "'#{string}'"]
    end


    ##
    # Build a command with sudo

    def sudo_cmd cmd, sudo_val=nil
      sudo_val = sudo_val[:sudo] if Hash === sudo_val
      sudo_val = @sudo if sudo_val.nil?

      case sudo_val
      when true
        ["sudo", cmd].flatten
      when String
        ["sudo", "-u", sudo_val, cmd].flatten
      else
        cmd
      end
    end


    ##
    # Write string to stdout (by default).

    def write str
      @output.write str
    end

    alias << write


    ##
    # Execute a command with open4 and loop until the process exits.
    # The cmd argument may be a string or an array. If a block is passed,
    # it will be called when data is received and passed the stream type
    # and stream string value:
    #   console.execute "test -s 'blah' && echo 'true'" do |stream, str|
    #     stream    #=> :stdout
    #     string    #=> 'true'
    #   end
    #
    # The method returns the output from the stdout stream by default, and
    # raises a CmdError if the exit status of the command is not zero.

    def execute cmd
      cmd = [cmd] unless Array === cmd
      pid, inn, out, err = popen4(*cmd)

      inn.sync = true
      log_methods = {out => :debug, err => :error}

      result, status = process_streams(pid, out, err) do |stream, data|
        stream_name = stream == out ? :out : :err

        Sunshine.logger.send log_methods[stream], ">>", data

        yield(stream_name, data) if block_given?

        if password_required?(stream_name, data) then

          kill_process(pid) unless Sunshine.interactive?

          send_password_to_stream(inn)

          data << "\n"
          Sunshine.console << "\n"
        end
      end

      raise_command_failed(status, cmd) unless status.success?

      result[out].join.chomp

    ensure
      inn.close rescue nil
      out.close rescue nil
      err.close rescue nil
    end


    private

    def raise_command_failed(status, cmd)
      raise CmdError,
        "Execution failed with status #{status.exitstatus}: #{[*cmd].join ' '}"
    end

    def password_required? stream_name, data
      stream_name == :err && data =~ SUDO_PROMPT
    end


    def send_password_to_stream inn
      inn.puts @password || prompt_for_password
    end


    def kill_process pid, kill_type="KILL"
      begin
        Process.kill kill_type, pid
        Process.wait
      rescue
      end
    end


    def process_streams pid, *streams
      result = Hash.new{|h,k| h[k] = []}

      # Handle process termination ourselves
      status = nil
      Thread.start do
        status = Process.waitpid2(pid).last
      end

      until streams.empty? do
        # don't busy loop
        selected, = select streams, nil, nil, 0.1

        next if selected.nil? or selected.empty?

        selected.each do |stream|

          if stream.eof? then
            streams.delete stream if status # we've quit, so no more writing
            next
          end

          data = stream.readpartial(1024)

          yield(stream, data)

          result[stream] << data
        end
      end

      return result, status
    end
  end
end
