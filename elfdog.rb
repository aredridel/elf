#! /usr/bin/ruby

$:.unshift(File.join(File.dirname(__FILE__), 'lib'))

require 'elf'
require 'amrita/xml'

require 'mongrel'
require 'camping'
require 'mongrel/camping'
#require 'auto-reload'

require 'elf/webrick'
require 'elf/queryservlet'

require 'optparse'
require 'yaml'

logger = Logger.new($stderr)
$logger = logger

port = 2000
debug = false
$config = File.join(File.dirname(__FILE__), 'db.yaml')

opts = OptionParser.new do |opts|
	opts.banner = "Usage: $0 [options]"
	opts.separator ""

	opts.on("-p", "--port [PORT]", Integer, "port to listen on") do |p|
		port = p
	end

	opts.on("-c", "--config [FILE]", "database configuration to load") do |c|
		$config = c
	end

	opts.on("-d", "--[no-]debug", "Enable debug mode") do |d|
		debug = d
	end

end

opts.parse!(ARGV)

#WEBrick::HTTPServlet::FileHandler.add_handler('rbsql', Elf::QueryHandler)

$config = YAML.load_file($config)

def db_connect
	ActiveRecord::Base.establish_connection(:adapter => 'postgresql', :host => $config['host'], :username => $config['username'], :password => $config['password'], :database => $config['database'], :logger => $logger)

	$dbh = ActiveRecord::Base.connection.connection
	Elf::DatabaseObject.dbh = $dbh
end

ActiveRecord::Base.establish_connection(:adapter => 'postgresql', :host => $config['host'], :username => $config['username'], :password => $config['password'], :database => $config['database'], :logger => $logger)

$dbh = ActiveRecord::Base.connection.connection
Elf::DatabaseObject.dbh = $dbh
#fc = WEBrick::HTTPServer.new(:Logger => logger, :Port => port, :Database => $dbh)

BasicSocket.do_not_reverse_lookup = true



options = Camping::H[
	'host' => '204.10.124.65',
	'port' => port,
	'daemon' => false,   'working_dir' => Dir.pwd,
	'server_log' => '-', 'log_level' => Logger::WARN
]

class Mongrel::WebrickHandler < Mongrel::HttpHandler
	def initialize(klass, *args)
		@klass = klass
		@args = args
	end

	def process(req, res)
		begin
			req_method = req.params[Mongrel::Const::REQUEST_METHOD] || Mongrel::Const::GET
			wrres = WEBrick::HTTPResponse.new(WEBrick::Config::HTTP)
			wrreq = WEBrick::HTTPRequest.new(WEBrick::Config::HTTP) 
			headers = "#{req_method} #{req.params['REQUEST_URI']} #{req.params['SERVER_PROTOCOL']}\n"
			req.params.each_pair do |k, v|
				if k =~ /^HTTP_(.*)/
					k = $1.split("_").map {|e| e.capitalize }.join("-")
					headers << "#{k}: #{v}\n"
				end
			end
			wrreq.parse(StringIO.new(headers + "\n" + req.instance_variable_get("@body").read))
			wrreq.path_info = req.params['PATH_INFO']
			@klass.new(WEBrick::Config::HTTP, *@args).send("do_" + req_method, wrreq, wrres)
			res.start(wrres.status) do |head, out|
				out.each { |h,v| head[h] = v }
				wrres.send_body(out)
			end
		rescue Exception => e
			$stderr.puts "#{e}: #{e.message}\n#{e.backtrace.join("\n\t")}"
		end
	end
end

config = Mongrel::Configurator.new :host => options.host do
	daemonize :cwd => options.working_dir, :log_file => options.server_log if options.daemon
	listener :port => options.port do
		uri '/',    :handler => Mongrel::DirHandler.new(File.dirname(__FILE__))
		uri '/o', :handler => Mongrel::WebrickHandler.new(Elf::ClassLoaderServlet)
		uri '/creditcards/batch', :handler => Mongrel::WebrickHandler.new(Elf::BatchServlet)
		uri '/forms', :handler => Mongrel::WebrickHandler.new(Elf::FormServlet)
		uri '/new', :handler => Mongrel::WebrickHandler.new(Elf::FactoryServlet)
		trap('INT') { stop }
		run
	end
end

config.join




