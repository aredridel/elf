require 'camping'
require 'elf/models'
require 'basic_authentication'

Camping.goes :ElfUser

module ElfUser
	include Camping::BasicAuth

	def self.authenticate(u, p)
		u == 'aredridel'
	end

	module Controllers
		class Index < R '/'
			def get
				render :index
			end
		end

		class Style < R '/(.*\.css)'
			def get(file)
				@headers['Content-Type'] = 'text/css'
				@body = File.read(File.join(File.dirname(__FILE__), file))
			end
		end

	end

	module Models
		include Elf::Models
	end

	module Views
		def index
			h1 'Customer Account'
		end

		def layout
			xhtml_strict do
				head do
					title "#{@page_title || ''}"
					link :rel => 'Stylesheet', :href=> '/site.css', :type => 'text/css'
				end
				body do
					h1 @page_title if @page_title
					self << yield
				end
			end
		end
	end
end
