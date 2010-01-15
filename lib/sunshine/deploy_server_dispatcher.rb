module Sunshine

  class DeployServerDispatcher < Array

    def initialize(*deploy_servers)
      self.add(*deploy_servers)
    end


    ##
    # Append a deploy server

    def <<(deploy_server)
      deploy_server = DeployServer.new(deploy_server) unless
        DeployServer === deploy_server
      self.push(deploy_server) unless self.exist?(deploy_server)
      self
    end


    ##
    # Add a list of deploy servers. Supports strings (user@server)
    # and DeployServer objects

    def add(*arr)
      arr.each do |ds|
        self << ds
      end
    end


    ##
    # Iterate over all deploy servers

    alias old_each each

    def each(&block)
      warn_if_empty
      self.old_each(&block)
    end


    ##
    # Find deploy servers matching the passed requirements
    # Returns a DeployServerDispatcher object
    #   find :user => 'db'
    #   find :host => 'someserver.com'
    #   find :role => :web

    def find(query=nil)
      return self if query.nil? || query == :all
      results = self.select do |ds|
        next unless ds.user == query[:user] if query[:user]
        next unless ds.host == query[:host] if query[:host]
        next unless ds.roles.include?(query[:role]) if query[:role]
        true
      end
      self.class.new(*results)
    end


    ##
    # Returns true if the dispatcher has a matching deploy_server

    def exist?(deploy_server)
      self.include? deploy_server
    end


    ##
    # Forwarding methods to deploy servers

    def connect(*args, &block)
      call_each_method :connect, *args, &block
    end

    def connected?
      self.each do |deploy_server|
        return false unless deploy_server.connected?
      end
      true
    end

    def disconnect(*args, &block)
      call_each_method :disconnect, *args, &block
    end

    def symlink(*args, &block)
      call_each_method :symlink, *args, &block
    end

    def upload(*args, &block)
      call_each_method :upload, *args, &block
    end

    def make_file(*args, &block)
      call_each_method :make_file, *args, &block
    end

    def run(*args, &block)
      call_each_method :run, *args, &block
    end

    alias call run


    private

    def call_each_method(method_name, *args, &block)
      self.each do |deploy_server|
        deploy_server.send(method_name, *args, &block)
      end
    end

    def warn_if_empty
      return unless self.empty?
      Sunshine.logger.warn :deploy_servers,
        "No deploy servers are configured. The action will not be executed."
    end
  end
end
