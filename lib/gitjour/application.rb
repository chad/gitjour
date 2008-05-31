require 'rubygems'
require 'dnssd'
require 'set'
Thread.abort_on_exception = true

module Gitjour
  GitService = Struct.new(:name, :host, :port, :description)  

  class Application

    class << self
      def run(options)
        @@verbose = options.verbose
        case options.command
          when "list"
            list
          when "clone"
            clone(options.name)
          when "serve"
            serve(options.name, options.path, options.port)
          when "remote"
            remote(options.name)
          else
            help
        end
      end

      private
			def list
				service_list.each do |service|
          puts "=== #{service.name} on #{service.host} ==="
          puts "  gitjour clone #{service.name}"
          puts "  #{service.description}" if service.description && service.description != '' && service.description !~ /^Unnamed repository/
          puts
        end
			end

      def get_host_and_share(repository_name)
        name_of_share = repository_name || fail("You have to pass in a name")
        host = service_list(name_of_share).detect{|service| service.name == name_of_share}.host rescue exit_with!("Couldn't find #{name_of_share}")
        system("git clone git://#{host}/ #{name_of_share}/")  
        [host, name_of_share]
      end

      def clone(name)
        service = service_list(name).detect{|service| service.name == name} rescue exit_with!("Couldn't find #{name}")
        cl("git clone git://#{service.host}:#{service.port}/ #{name}/")
      end

      def remote(repository_name,*rest)
        host, name_of_share = get_host_and_share(repository_name)
        system("git remote add #{name_of_share} git://#{host}/")
      end

      def serve(path, port)
        path ||= Dir.pwd
        path = File.expand_path(path)
        File.exists?("#{path}/.git") ? announce_repo(path, port) : Dir["#{path}/*"].each_with_index{|dir,i| announce_repo(dir, port+i) if File.directory?(dir)}
        cl("git-daemon --verbose --export-all --port=#{port} --base-path=#{path} --base-path-relaxed")
      end

      def exit_with!(message)
        STDERR.puts message
        exit!
      end

      def service_list(looking_for = nil)
        wait_seconds = 5

        service_list = Set.new
        waiting_thread = Thread.new { sleep wait_seconds }

        service = DNSSD.browse "_git._tcp" do |reply|
          DNSSD.resolve reply.name, reply.type, reply.domain do |resolve_reply|
            service_list << GitService.new(reply.name, resolve_reply.target, resolve_reply.port, resolve_reply.text_record['description'])
            if looking_for && reply.name == looking_for
              waiting_thread.kill
            end
          end
        end
        puts "Gathering for up to #{wait_seconds} seconds..."
        waiting_thread.join
        service.stop
        service_list
      end

      def announce_repo(name, path, port)
        return unless File.exists?("#{path}/.git")
        name = share_name || File.basename(path)
        tr = DNSSD::TextRecord.new
        tr['description'] = File.read(".git/description") rescue "a git project"
        DNSSD.register(name, "_git._tcp", 'local', port, tr.encode) do |register_reply| 
          puts "Registered #{name}.  Starting service."
        end
      end
      
      def cl(command)
        output = `#{command}`
        if @@verbose
          puts command
          puts output
        end
      end
    end
  end
end



