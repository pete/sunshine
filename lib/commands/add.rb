module Sunshine

  module AddCommand

    ##
    # Runs the command and returns:
    #   true: success
    #   false: failed
    #   exitcode:
    #     code == 0: success
    #     code != 0: failed
    # and optionally an accompanying message.

    def self.exec app_paths, config
      errors = false
      verbose = config['verbose']

      ListCommand.each_server_list(config['servers']) do |apps, server|
        puts "Updating #{host}..." if verbose

        app_paths.each do |path|
          app_name, path = path.split(":") if path.include?(":")
          app_name ||= File.basename path

          unless (server.run "test -d #{path}" rescue false)
            puts "  #{path} is not a valid directory"
            errors = true
            next
          end

          apps[app_name] = path

          Sunshine.console << "  add: #{app_name} -> #{path}" if verbose
        end

        ListCommand.save_list apps, server
      end

      return !errors
    end


    def self.parse_args argv

      DefaultCommand.parse_remote_args(argv) do |opt, options|
        opt.banner = <<-EOF

Usage: #{opt.program_name} add app_path [more paths...] [options]

Arguments:
    app_path      Path to the application to add.
                  A name may be assigned to the app by specifying name:app_path.
                  By default: name = File.basename app_path
        EOF
      end
    end
  end
end
