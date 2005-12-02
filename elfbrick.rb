#! /usr/bin/ruby

$:.unshift(File.join(File.dirname(__FILE__), 'lib'))

require 'elf'

require 'webrick'
#require 'auto-reload'

require 'elf/webrick'
require 'elf/queryservlet'

require 'optparse'
require 'yaml'

logger = Logger.new($stderr)
$logger = logger

class ExitApplet < WEBrick::HTTPServlet::AbstractServlet
	def do_GET(r,res)
		exit
	end
end

port = 2000
debug = false
config = File.join(File.dirname(__FILE__), 'db.yaml')

opts = OptionParser.new do |opts|
	opts.banner = "Usage: $0 [options]"
	opts.separator ""

	opts.on("-p", "--port [PORT]", Integer, "port to listen on") do |p|
		port = p
	end

	opts.on("-c", "--config [FILE]", "database configuration to load") do |c|
		config = c
	end

	opts.on("-d", "--[no-]debug", "Enable debug mode") do |d|
		debug = d
	end

end

opts.parse!(ARGV)

WEBrick::HTTPServlet::FileHandler.add_handler('rbsql', Elf::QueryHandler)

config = YAML.load_file(config)

class ActiveRecord::ConnectionAdapters::AbstractAdapter
	attr_accessor :connection
end

ActiveRecord::Base.establish_connection(:adapter => 'postgresql', :host => config['host'], :username => config['username'], :password => config['password'], :database => config['database'], :logger => $logger)

$dbh = ActiveRecord::Base.connection.connection
Elf::DatabaseObject.dbh = $dbh
fc = WEBrick::HTTPServer.new(:Logger => logger, :Port => port, :Database => $dbh)

trap("INT") {
	fc.stop
}
fc.mount('/', WEBrick::HTTPServlet::FileHandler, File.dirname(__FILE__))
fc.mount('/o', Elf::ClassLoaderServlet)
fc.mount('/creditcards/batch', Elf::BatchServlet)
fc.mount('/forms', Elf::FormServlet)
fc.mount('/new', Elf::FactoryServlet)
fc.mount('/exit', ExitApplet)
fc.start
