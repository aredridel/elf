require 'test/unit'
require 'mvc/website'
require 'webrick/fcgi/tests'

module MVC::Website::Tests

class TestBase < Test::Unit::TestCase
	def setup
		@app = Application.new
	end
	def test_virtual_run
		begin
			@app.run
		rescue Exception
			assert(Application::NotImplemented, $!)
		end
	end

	def test_protect
		begin
			oe = $stderr
			$stderr = File.open("/dev/null", "w")
			@app.protect do
				raise "testing!"
			end
			$stderr = oe
			assert(true, true)
		end
	end
end

end
