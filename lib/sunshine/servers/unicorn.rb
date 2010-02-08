module Sunshine

  ##
  # Simple server wrapper for Unicorn setup and control.

  class Unicorn < Server

    def initialize app, options={}
      super
      @timeout = options[:timeout] || 3.0
    end


    def start_cmd
      "cd #{@app.current_path} && #{@bin} -D -E"+
        " #{@app.deploy_env} -p #{@port} -c #{self.config_file_path};"
    end


    def stop_cmd
      "test -f #{@pid} && kill -QUIT $(cat #{@pid})"+
        " || echo 'No #{@name} process to stop for #{@app.name}';"+
        "sleep 2; rm -f #{@pid};"
    end
  end
end
