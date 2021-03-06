module Sunshine

  ##
  # Runs the restart script of all specified sunshine apps.
  #
  # Usage: sunshine restart [options] app_name [more names...]
  #
  # Arguments:
  #     app_name     Name of the application to restart.
  #
  # Options:
  #   -f, --format FORMAT        Set the output format (txt, yml, json)
  #   -u, --user USER            User to use for remote login. Use with -r.
  #   -r, --remote svr1,svr2     Run on one or more remote servers.
  #   -S, --sudo                 Run remote commands using sudo or sudo -u USER
  #   -v, --verbose              Run in verbose mode.

  class RestartCommand < ListCommand

    ##
    # Takes an array and a hash, runs the command and returns:
    #   true: success
    #   false: failed
    #   exitcode:
    #     code == 0: success
    #     code != 0: failed
    # and optionally an accompanying message.

    def self.exec names, config
      output = exec_each_server config do |shell|
        new(shell).restart(names)
      end

      return output
    end


    ##
    # Restart specified apps.

    def restart app_names
      status_after_command :restart, app_names, :sudo => false
    end


    ##
    # Parses the argv passed to the command

    def self.parse_args argv
      parse_remote_args(argv) do |opt, options|
        opt.banner = <<-EOF

Usage: #{opt.program_name} restart [options] app_name [more names...]

Arguments:
    app_name     Name of the application to restart.
        EOF

      end
    end
  end
end

