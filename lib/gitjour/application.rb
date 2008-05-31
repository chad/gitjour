require 'dnssd'
require 'set'
Thread.abort_on_exception = true

module Gitjour
  GitService = Struct.new(:name, :host, :description)  
  class Application

    def self.service_list(looking_for = nil)
      wait_seconds = 5

      service_list = Set.new  
      waiting_thread = Thread.new { sleep wait_seconds }

      service = DNSSD.browse "_git._tcp" do |reply|
        DNSSD.resolve reply.name, reply.type, reply.domain do |resolve_reply|
          service_list << GitService.new(reply.name, resolve_reply.target, resolve_reply.text_record['description'])
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
    def self.run(operation, argument = nil)
      case operation
        when "list"
          service_list.each do |service|
            puts "#{service.name} on #{service.host}: gitjour clone #{service.name}"
            puts "  #{service.description}" if service.description && service.description != ''
          end
        when "clone"
          name_of_share = argument || fail("You have to pass in a name")
          host = service_list(name_of_share).detect{|service| service.name == name_of_share}.host rescue exit_with!("Couldn't find #{name_of_share}")
          system("git clone git://#{host}/ #{name_of_share}/")
        when "serve"
          path = File.expand_path(argument) || Dir.pwd
          File.exists?("#{path}/.git") ? announce_repo(path) : Dir["#{path}/*"].each{|dir| announce_repo(dir) if File.directory?(dir)}
          `git-daemon --verbose --export-all --base-path=#{path} --base-path-relaxed`
        else
          puts "Serve up and use git repositories via Bonjour/DNSSD."
          puts "Usage: gitjour <command> [name]"
          puts
          puts "  list      Lists available repositories."
          puts "  clone     Clone a gitjour served repository."
          puts "  serve     Serve up the current directory via gitjour."
          puts "            Optionally pass name to not use pwd."
          puts
      end
    end
    def self.exit_with!(message)
      STDERR.puts message
      exit!
    end
    
    protected 

    def self.announce_repo(path)
      return unless File.exists?("#{path}/.git")
      name = "#{File.basename(path)}"
      tr = DNSSD::TextRecord.new
      tr['description'] = File.read(".git/description") rescue "a git project"
      DNSSD.register(name, "_git._tcp", 'local', 9148, tr.encode) do |register_reply| 
        puts "Registered #{name}.  Starting service."
      end
    end
  end
end



