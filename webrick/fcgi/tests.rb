require 'test/unit'

class TestFCGI < Test::Unit::TestCase
	class ::FCGIWebApplication
		def root_element
			{ 'foo' => { 'bar' => "Yay!" } } 
		end
	end
	class MockFCGIRequest < WEBrick::HTTPRequest
		def initialize(path = nil)
			if path.nil?
				@path = '/'
			else
				@path = path
			end
			@in = StringIO.new
			@out = StringIO.new
		end


		attr_accessor :out, :in

		attr_accessor :path 
		
		alias :unparsed_uri :path

		def env
			return {'PATH_INFO' => path.to_s, 'REQUEST_METHOD' => 'GET', 
				'HTTP_CONNECTION' => 'close', 'HTTP_USER_AGENT' => 'Test', 'QUERY_STRING' => 'foo=bar' }
		end
		def finish
		end
	end

	class MockModel
		def data
			{'item' => 'Yay!'}
		end
	end
	class ::FCGI
		def self.each
			yield default_request
		end
		class << self
			def default_request
				if @default_request
					@default_request
				else 
					MockFCGIRequest.new('/foo/bar')
				end
			end
			attr_writer :default_request
		end
	end

	def setup
		$stderr.sync = true
		$stdout.sync = true
		@logger = Logger.new($stderr)
		@logger.level = Logger::WARN
		@app = WEBrick::FCGIServer.new(:Logger => @logger)
	end

	def test1_test_framework
		FCGI.each do |req, response|
			assert(req.class, MockFCGIRequest)
			assert(req.env.size >= 4)
		end
	end

	def test_app
		FCGI.default_request = MockFCGIRequest.new('/yourmom')
		output = nil
		@app.run do |request, response|
			request.out.seek(0)
			output = request.out.read(16000)
		end
		assert(!output.empty?)
		assert(output =~ /Status/)
		assert(!(output =~ /^HTTP/))
	end

	def test_mount
		@app.mount('/servlet', WEBrick::HTTPServlet::DefaultFileHandler.new(@app, '/'))
	end

	def test_failure
		FCGI.default_request = MockFCGIRequest.new('/bad/request')
		output = nil      
		@app.run do |request, response|
			request.out.seek(0)
			assert(response.status == 404)
			output = request.out.read(16000)
		end
		assert(!output.empty?)
	end

	def test_redirect
		FCGI.default_request = MockFCGIRequest.new('')
		@app.run do |r, response|
			assert(response.status == 301)
		end
	end

	def test2_requests
		req = MockFCGIRequest.new('/data/item')
		assert(!req.env['REQUEST_METHOD'].empty?, true)
		assert_equal(req.env['PATH_INFO'], '/data/item')
		result = @app.service(req, WEBrick::FCGIResponse.new(@app.config))
	end
end
