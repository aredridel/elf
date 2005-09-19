require 'fcgi'
require 'webrick'

class String
	def ucfirst
		self[0, 1].upcase + self[1..-1]
	end
end

module WEBrick 
	class FCGIRequest < HTTPRequest
		alias :HTTPParse :parse
		def parse(cgirequest)
			env = cgirequest.env
			s = ''
			s << "#{env['REQUEST_METHOD']} #{env['PATH_INFO']}#{if env['QUERY_STRING'] then "?#{env['QUERY_STRING']}" else "" end} #{env['SERVER_PROTOCOL']}\n"
			cgirequest.env.each_pair do |k,v|
				s << "#{k.sub(/^HTTP_/, '').downcase!.capitalize}: #{v}\n" if /^HTTP_/ =~ k
			end
			if !cgirequest.in.string.empty?
				s << "Content-length: #{cgirequest.in.string.length}\n"
				s << "\n#{cgirequest.in.string}"
			end
			self.HTTPParse StringIO.new(s)
			self
		end
	end
	class FCGIResponse < HTTPResponse
		def initialize(options)
			@body = ""
			super
		end
		CRLF = WEBrick::CRLF
		def status_line
			"Status: #@status #@reason_phrase #{CRLF}"
		end
	end

	module Config
		FCGI = HTTP.dup.update(:DoNotListen => true, :HTTPVersion => '1.1')
	end

	class FCGIServer < HTTPServer
		def initialize(config = {}, default = Config::FCGI)
			super

			@config.update(config)

			@mount_tab = HTTPServer::MountTable.new
			if @config[:DocumentRoot]
			  mount("/", HTTPServlet::FileHandler, @config[:DocumentRoot],
					  @config[:DocumentRootOptions])
			end

			unless @config[:AccessLog]
			  @config[:AccessLog] = [
				 [ $stderr, AccessLog::COMMON_LOG_FORMAT ],
				 [ $stderr, AccessLog::REFERER_LOG_FORMAT ]
			  ]
			end
		end

		def start
			shutdown = false

			Signal.trap("TERM") do
				exit
			end

			Signal.trap("USR1") do
				shutdown = true
			end

			FCGI.each do |fcgi|
				exit if shutdown
				begin
					res = WEBrick::FCGIResponse.new(@config)
					req = WEBrick::FCGIRequest.new(@config)
					res.status = 200
					res.body = ''
					if fcgi.env['PATH_INFO'].nil? or fcgi.env['PATH_INFO'].empty?
						res.status = 301
						res['location'] = '/'
					else
						req.parse(fcgi)
						res.request_method = req.request_method
						res.request_uri = req.request_uri
						res.request_http_version = req.http_version
						res.keep_alive = req.keep_alive?
						if handler = @config[:RequestHandler]
							handler.call(req, res)
						end
						service(req, res)
					end
				rescue HTTPStatus::EOFError, HTTPStatus::RequestTimeout => ex
					res.set_error(ex)
				rescue HTTPStatus::Error => ex
					res.set_error(ex)
				rescue HTTPStatus::Status => ex
					res.status = ex.code
				rescue Exception
					@logger.warn "Whoops -- #{$!}: #{$!.backtrace[0]}"
					res.body = "Whoops -- #{$!}: #{$!.backtrace.join("\n")}"
					res.status = 500
					res['content-type'] = 'text/plain'
				end
				if res['location'] and res['location'][0] = '/'
					res['location'] = fcgi.env['SCRIPT_NAME'] + res['location']
				end
				res.send_response(fcgi.out)
				yield fcgi, res if block_given?
				fcgi.finish
			end
		end

		alias :run :start

		def service(req, res)
			if req.unparsed_uri == "*"
				if req.request_method == "OPTIONS"
					do_OPTIONS(req, res)
					raise HTTPStatus::OK
				end
				raise HTTPStatus::NotFound, "'#{req.unparsed_uri}' not found."
			end

			servlet, options, script_name, path_info = search_servlet(req.path)
			raise HTTPStatus::NotFound, "'#{req.path}' not found." unless servlet
			req.script_name = script_name
			req.path_info = path_info
			si = servlet.get_instance(self, *options)
			@logger.debug { format("%s is invoked.", si.class.name) }
			si.service(req, res)
		end


		def mount(dir, servlet, *options)
			@logger.debug { sprintf("%s is mounted on %s.", servlet.inspect, dir) }
			@mount_tab[dir] = [ servlet, options ]
		end

					
		def root_element
			ExampleComponent.new
		end
	end
end
