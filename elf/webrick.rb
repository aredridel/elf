require 'elf'

module Elf
	# Servlet that ... well, nobody knows, exactly.
	class DatabaseServlet < WEBrick::HTTPServlet::AbstractServlet
		def parse_query_string(s)
			params = Hash.new { |h,k| h[k] = Array.new }
			s.gsub!('+', ' ')
			if s
				s.split('&').map{|e| e.split('=')}.each {|n| params[n[0]] << n[1] }
			end
			params.each_key do |k| 
				params[k].map do |n|
					n.gsub!(/%[0-9A-F]{2}/i) do |match|
						#$stderr.puts("params[k]: #{params[k]}; match: #{match.inspect}")
						match[1..2].to_i(16).chr
					end if n
				end
			end
		end
	end

	class MainServlet < DatabaseServlet
		def do_GET(req, res)
			res.body = ""
			list = Customer.find_all("name = 'rick'")
			res.body << "Rows: #{list.size}<br />"
			list.each do |s|
				res.body << REXML::Text.new(s.inspect).to_s
			end
			#res.body << REXML::Text.new("List: #{list.inspect}").to_s << "<br />"
			#res.body << REXML::Text.new("Request: #{req.inspect}").to_s << "<br />"
			res['content-type'] = 'text/plain'
		end
	end

	class ClassLoaderServlet < DatabaseServlet
		def do_GET(req, res)
			res.body = ''
			try = 0
			begin
				uri = URI::parse("http://#{req.host}#{req.path_info}?#{req.query_string}")
				#res.body << req.inspect
				#res.body << uri.to_s
				res['content-type'] = 'text/html; charset=UTF-8'
				controller = MVC::Website::URIController.new
				instance = controller.instance_for_uri(uri)
				view = controller.view_for_uri(uri)
				if Array === instance and instance.size > 0
					data = { 
						(instance[0].class.basename.plural.gsub(/([a-z])([A-Z])/, '\1_\2').downcase).intern => instance 
					}
					if instance[0].class.aggregates.size > 0
						instance[0].class.aggregates.keys.each do |k|
							data[k] = instance.send(k)
						end
					end
					data.merge! instance[0].list_data
					$logger.debug { data.inspect } 
					view.expand res.body, data
				else
					view.expand res.body, instance
				end
				try = 0
			rescue ActiveRecord::StatementInvalid => e
				try += 1
				if try <= 5
					db_connect
					retry
				else
					raise
				end
			rescue Exception => e
				res.status = 500
				res['content-type'] = 'text/plain'
				res.body << e.class.name.to_s + ", " + e.message + e.backtrace.join("\n");
			end
		end
	end

	class FactoryServlet < DatabaseServlet
		def do_GET(req, res)
			raise WEBrick::HTTPStatus::ServerError
		end
		def do_POST(req, res)
			klass = eval(File::basename(req.path_info).capitalize)
			o = klass.new
			params = parse_query_string(req.body)
			#$stderr.puts("req = #{req.inspect}")
			params.each_pair do |k,v|
				$stderr.puts("#{k} = #{v.inspect}")
				if v.kind_of? Array
					v = v[0]
				end
				if v and !v.empty?
					#$stderr.puts("Setting #{k}=#{v}")
					o.send("#{k}=".intern, v)
				end
			end
			o.validate
			o.save
			template = Amrita::XMLTemplateFile.new('save-successful.html')
			res.body = ''
			res['content-type'] = 'text/html; charset=UTF-8'
			template.expand(res.body, {:return => req['Referer']})
		end
	end

	class FormServlet < DatabaseServlet
		def do_GET(req, res)
			template = Amrita::XMLTemplateFile.new(File::basename(req.path_info)+'.html')
			res.body = ''
			res['content-type'] = 'text/html; charset=UTF-8'
			params = parse_query_string(req.query_string)
			data = {}
			params.each_pair do |k,v|
				data[k.intern] = v
			end
			template.expand(res.body, data)
		end
	end

	# Servlet to find and show a customer
	class CustomerServlet < DatabaseServlet
		def do_GET(req, res)
			params = parse_query_string(req.query_string)
			res['content-type'] = 'text/html; charset=UTF-8'
			if params['find'].size >= 1
				@logger.debug { "Handling #{req.query_string}" }
				customers = Customer.find_all("name = '#{params['find'][0]}'")
				res.status = 302
				res['Location'] = '/elf/elf.rbx/' << customers[0].uri
				#res.body = customers.inspect
			elsif !req.path_info.empty?
				@logger.debug { "Handling #{req.path_info}" }
				customer = Customer.find_first("name = '#{File.basename(req.path_info)}'")
				t = Amrita::TemplateFile.new("customer.html")
				t.xml = true
				t.amrita_id = 'amrita:id'
				t.asxml = true
				t.expand res.body, customer
			else
				# raise error
			end
		end
	end

		class BatchServlet < DatabaseServlet
			class ChargeLine
				attr_accessor :first, :last, :company, :street, :city, :state, :zip, :phone, :email 
				attr_accessor :invoice, :amount, :cardnumber, :cardexpire, :customer_id
				def cvv
					nil
				end
				def cvv=(other)
					other
				end
				def initialize(h = {})
					h.keys.each {|key| self.send((key.to_s+'=').intern, h[key])}
					raise 'no cardnumber' if cardnumber.nil?
					raise 'no expiration' if cardexpire.nil?
					raise 'no amount' if amount.nil?
					raise 'no customer id' if customer_id.nil?
				end
				def to_s
					[
						invoice, "%.2f" % amount,
						"CC", "AUTH_CAPTURE", 
						cardnumber.gsub(/[^0-9]/, ''), cardexpire, cvv, 
						customer_id, 
						first, last, company, 
						street, city, state, zip, phone, email
						].map{|e| if e.nil? then "" else e end }.join("\t") << "\n"
				end
			end
			def do_GET(req, res)
				res.body = ""
				res['content-type'] = 'text/plain'
				res['content-disposition'] = 'attachment; filename=batch.txt'
				total = 0
				filter = "and account_id is not null and billto is null and cardnumber is not null and cardexpire is not null"
				CreditCards::CardBatch.find_first("status = 'In Progress'").items.each do |item|
					customer = item.customer
					$logger.debug { "Processing #{customer.name}" }
					next if customer.cardnumber.nil? or customer.cardexpire.nil?
					exp = customer.cardexpire.strftime('%Y%M')
					next if customer.cardexpire < Date.today
					account = customer.account
					amount = item.amount
					next if amount <= 0
					next if account.balance <= 0
					params = {:first => customer.first, :last => customer.last, :invoice => item.invoice_id, :amount => amount, :company => customer.company, :phone => customer.phones[0] || nil, :email => customer.emailto, :cardnumber => customer.cardnumber, :cardexpire => customer.cardexpire, :cvv => nil, :customer_id => customer.name}
					params.update(:street => customer.addresses[0].street, :city => customer.addresses[0].city, :state => customer.addresses[0].state, :zip => customer.addresses[0].zip) if customer.addresses[0]
					res.body << ChargeLine.new(params).to_s
				end
			end
		end

end
