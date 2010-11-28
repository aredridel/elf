module Elf
	class QueryHandler < WEBrick::HTTPServlet::AbstractServlet

		class TableFormatter
			def self.row(row, tag = 'td')
				start = "<#{tag}>"
				tend = "</#{tag}>"
				'<tr>' + row.map {|e| start + if e: e else '<em>null</em>' end + tend }.join + '</tr>'
			end
			def self.start
				'<table>' + yield + '</table>'
			end
		end

		def initialize(server, name)
			super
			@script_filename = name
			@db = server[:Database]
		end
		def do_GET(req,res)
			res['content-type'] = 'text/html'
			query = File.read(@script_filename)
			result = @db.exec query

			res.body = TableFormatter.start do
				result.map { |e| TableFormatter.row(e) }.join
			end
		end
	end
end
