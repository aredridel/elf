require 'elf'
require 'db-connection'
require 'ostruct'
require 'logger'
require 'elf/webrick'

$logger = Logger.new(STDERR)


s = OpenStruct.new
class << s
	def [](n)
		self.send n
	end
	def []=(n,v)
		self.send n+'=', v
	end
end
Elf::BatchServlet.new("").do_GET("", s)
puts s.body
