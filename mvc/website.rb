#! /usr/bin/ruby

require 'pathname'
require 'webrick'
require 'webrick/fcgi'
require 'fcgi'
require 'stringio'
require 'logger'

module MVC
	module Website
		class WebException < Exception
		end
		class NotFound < WebException
		end
	end
end

class Application
	class NotImplemented < Exception
	end
		
	def run
		raise NotImplemented
	end

	def protect
		begin
			yield
		rescue Exception
			$stderr.puts "Whoops -- #{$!}: #{$!.backtrace.join("\n")}"
		end
	end
end

class WebApplication < Application
	def protect
		 begin
			 yield
		 rescue Exception
			 $stderr.puts "Whoops -- #{$!}: #{$!.backtrace.join("\n")}"
		 end
	end
end

class ExampleComponent
	def yourmom
		"Your mom."
	end
end


class FCGIWebApplication < WebApplication
end


class PathComponent
	def initialize(component, scope)
		@component = component
		@scope = scope
	end

	attr_accessor :component
	attr_accessor :scope

	def to_s
		component + 
		if scope == 'sub' or scope == 'one'
			'/' 
		else 
			'' 
		end
	end
end

class PathSearch
	def initialize(path)
		if path.to_a.last == '/'
			@scope = one
		end
	end
end

module Unused
	class FCGI
		def handle_request(request, component, response)
			result = component
			Pathname.new(request.path).each_filename do |m|
				if result.respond_to? :[]
					result = result[m]
				elsif result.respond_to? m.intern
					if result.method(m.intern).arity == 1
						result = result.send m.intern, request
					else
						result = result.send m.intern
					end
				else raise HTTPStatus::NotFound
				end
			end
			result
		end
	end
end
