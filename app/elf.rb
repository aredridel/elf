# encoding: utf-8
#
# * Platypus imagines comments....
# <Platypus> // Fred 0.99b
# <Platypus> // A perpetually nervous man in the corner with an abacus.

# Elf. A gnarled, ancient wizardly sort, sitting in the corner, reading slips
# of paper written in an arcane script. He has no other name than simply "Elf".

$:.unshift(File.join(File.dirname(__FILE__), 'local'))

require 'date'
require 'date4/delta'
require 'camping'

Camping.goes :Elf

require 'markaby'

require 'rexml/doctype'
require 'rexml/text'
require 'amrita/template'
require 'enumerator'
require 'uri'
require 'set'
require 'active_record'
require 'rmail'
require 'time'
require 'delegate'
require 'base64'
require 'net/smtp'
require 'elf/utility'
require 'ar-fixes'
require 'active_merchant'

require 'elf/models'
require 'elf/accounts'
require 'elf/deposits'
require 'elf/vendors'

require 'camping/mab'

module Elf
	module Base
		MAB_OPTS = {
			:indent                 => 2,
			:auto_validation        => true,
			:tagset                 => Markaby::HTML5,
			:root_attributes => {
				:lang       => 'en'
			}
		}
		def mab(&b)
			(@mab ||= Mab.new(MAB_OPTS,self)).capture(&b)
		end

		def accepts
			@env["HTTP_ACCEPT"].to_s.split(/,\s*/).map do |part|
				m = /^([^\s,]+?)(?:;\s*q=(\d+(?:\.\d+)?))?$/.match(part) # From WEBrick
				if m
					[m[1], (m[2] || 1.0).to_f]
				else
					raise "Invalid value for Accept: #{part.inspect}"
				end
			end
		end
	end

	module Helpers

		def const_get_r(name)
			name.split('::').inject(Object) { |a,e| a.const_get(e) }
		end

		def getcontact(id)
			begin
				Elf::Contact.find(Integer(id)) 
			rescue ArgumentError => e
				Elf::Contact.find_by_name(id)
			end
		end

		def cache(klass, key = 'new', *args)
			$cache ||= Hash.new { |h,k|
				if k.last == 'new'
					h[k] = const_get_r(k[0]).new
				else
					h[k] = const_get_r(k[0]).find(k.last)
				end
			}

			$cache[[klass.name, key.to_s, *args]]
		end

		def cachekey(klass, key, *args)
			[klass.name, key.to_s, *args]
		end
	end

	class DatabaseObject
		def self.dbh=(d)
			@@dbh = d
		end

		def protected
			status = :go
			begin
				@@dbh.exec "BEGIN WORK"
				return yield(@@dbh)
			rescue
				@@dbh.exec "ABORT"
				raise
			ensure
				@@dbh.exec "COMMIT" unless status == :abort
			end
		end
	end

	def self.monthlybilling(month, message = nil)
		batch = Elf::CardBatch.create(:status => 'In Progress', :date => Date.today)
		Elf::Contact.find_all.map do |c|
			begin
				i = c.generate_invoice(true, (month)..((month >> 1) - 1), 'Monthly')
				if i
					#i.send_by_email(:with_message => message)
					if c.cardnumber and c.cardexpire
						opts = {
							:amount => i.total, 
							:first => c.first, 
							:last => c.last, 
							:name => c.name, 
							:customer_id => c.id, 
							:payment_type => 'CC', 
							:transaction_type => 'AUTH_CAPTURE', 
							:cardnumber => c.cardnumber, 
							:cardexpire => c.cardexpire
						}
						if c.city and c.state and c.zip
							opts.update Hash[
								:city => c.city, 
								:state => c.state, 
								:zip => c.zip, 
							]
						end
						if opts[:amount] and opts[:amount] > 0
							batch.items << item = CardBatchItem.new(opts)
							item.charge!
						end
					end
				end
			rescue Exception
				puts "#{$!}: #{$!.message}: #{$!.backtrace.join("\n\t")}"
			end
			batch.save
			true
		end
	end

	include Models

	module Controllers

		class CardBatchList < R '/cardbatches/list'
			def get
				@batches = CardBatch.find(:all, :order => 'id DESC')
				render :cardbatchlist
			end
		end

		class CardBatchView < R '/cardbatches/(\d+)'
			def get(id)
				@batch = CardBatch.find(id)
				render :cardbatchview
			end
		end

		class CardBatchSend < R '/cardbatches/(\d+)/send'
			def post(id)
				@batch = CardBatch.find(id)
				@batch.send!
				redirect R(CardBatchView, id)
			end
		end

		class CardExpirationList < R '/reports/expired_cards'
			def get
				@contacts = Contact.find(:all, :conditions => 'cardnumber is not null and cardexpire < now()', :order => 'cardexpire DESC')
				@contacts = @contacts.select { |e| e.account.balance > Money.new(0) or e.active_services.length > 0 }
				@page_title = 'Card Expiration List'
				render :cardexpirationlist
			end
		end

		class CustomerList < R '/customers/'
			def get
				if @input.q
					search = @input.q
					@contacts = Elf::Models::Contact.find(:all, :conditions => ["name ilike ? or first ilike ? or last ilike ? or organization ilike ? or emailto ilike ? or id in (select contact_id from phones where phone like ?)", *(["%#{@input.q}%"] * 6)], :order => 'first, last')
				else
					@contacts = Elf::Contact.find(:all, :order => 'name')
				end
				if @input.q
					@page_title =  "Customers matching \"#{@input.q}\""
				else
					@page_title = 'Customer list'
				end
				render :customerlist
			end
		end

		class OpenInvoices < R '/invoices/open'
			def get
				@page_title = 'Customers with open invoices'
				@open_invoices = Invoice.find(:all, :conditions => "status = 'Open'", :order => 'id')
				@contacts = @open_invoices.map { |i| i.account.contact }
				render :customerlist
			end
		end

		class CustomerBalanceAndServiceList < R '/reports/high_balances'
			def get
				@contacts = Contact.find(:all)
				@contacts = @contacts.select { |e| e.account.balance > Money.new(5000) }.sort_by { |c| -(c.account.balance * (c.active_services.length + 1)).cents }
				@page_title = 'High balances'
				render :customerlist, :customerhighbalances 
			end
		end

		class CustomerOverview < R '/customers/(\d+|[^/]+)/'
			def get(id)
				@contact = getcontact(id)
				@page_title = 'Account overview for ' + @contact.account_name
				render :customeroverview
			end
		end

		class ContactEdit < R '/contacts/(\d+|[^/]+)/edit'
			def get(id)
				if id == 'new'
					@contact = Elf::Contact.new
				else
					@contact = getcontact(id)
				end
				@page_title = 'Edit contact'
				render :contactedit
			end

			def post(id)
				if id == 'new'
					@contact = Elf::Company.find(1).contacts.build
				else
					@contact = getcontact(id)
				end
				["name", "first", "last", "organization", "emailto", "street", "street2", "city", "state", "postal", "country"].each do |s|
					v = @input[s]
					v = nil if v.empty?
					@contact.send("#{s}=", v)
				end
				if @contact.new_record?
					@contact.accounts << Elf::Account.new(mtime: Time.now, description: "Receivable: " + @contact.name, contact: @contact)
				end
				@contact.save!
				redirect R(CustomerOverview, @contact.id)
			end
		end

		class CustomerAddPhone < R '/customers/(\d+|[^/]+)/phone/new'
			def get(id)
				@contact = getcontact(id)
				render :customeraddphone
			end
			def post(id)
				@contact = getcontact(id)
				@contact.phones << Elf::Phone.new(:phone => @input.phone, :which => @input.which)
				@contact.save!
				redirect R(CustomerOverview, @contact.id)
			end
		end

		class CustomerServiceNew < R '/customers/(\d+|[^/]+)/services/new'
			def get(id)
				@contact = getcontact(id)
				render :customerservicenew
			end
			def post(id)
				@contact = getcontact(id)
				@service = Elf::Service.new
				@service.contact = @contact
				@service.amount = Money.new(@input.amount.to_f * 100, 'USD')
				@service.detail = @input.detail
				@service.service = @input.service
				@service.period = @input.period
				if @input.starts =~ /Now/
					@service.starts = Time.now
				else
					@service.starts = Date.parse @input.starts
				end
				@service.nextbilling = @service.starts
				@service.save!
				redirect R(CustomerOverview, @contact.id)
			end
		end

		class RemoveCard < R '/customers/(\d+|[^/]+)/removecard'
			def get(id)
				@contact = getcontact(id)
				render :removecard
			end

			def post(id)
				@contact = getcontact(id)
				@contact.cardnumber = nil
				@contact.cardexpire = nil
				@contact.save!
				redirect R(CustomerOverview, @contact.id)
			end
		end

		class ChargeCard < R '/customers/(\d+|[^/])/chargecard'
			def get(id)
				@contact = getcontact(id)
				render :chargecard
			end

			def post(id)
				@contact = getcontact(id)
				cn = if @input.cardnumber and @input.cardnumber.length > 12
					@input.cardnumber
				else
					nil
				end
				exp = Date.parse(@input.cardexpire) rescue nil
				response = @contact.charge_card(Money.new(BigDecimal.new(@input.amount) * 100), cn, exp)
				if response.success?
					redirect R(CustomerOverview, @contact.id)
				else
					raise StandardError, response.message 
				end
			end
		end

		class CustomerUpdateCC < R '/customers/(\d+|[^/]+)/newcc'
			def get(customer)
				@contact = getcontact(customer)
				@page_title = 'Update CC #'
				render :customerupdatecc
			end
			def post(customer)
				@contact = getcontact(customer)
				@contact.cardnumber = @input.newcc if @input.newcc and !@input.newcc.empty?
				@contact.cardexpire = Date.parse(@input.newexp) if @input.newexp and !@input.newexp.empty?
				@contact.save!
				redirect R(CustomerOverview, @contact.id)
			end
		end

		class DomainDelete < R '/domain/([^/]+)/delete'
			def	get(domain)
				@domain = Domain.find(:first, :conditions => ['name = ?', domain])
				render :domaindeleteconfirm
			end
			def post(domain)
				@domain = Domain.find(:first, :conditions => ['name = ?', domain])
				@domain.destroy
				redirect R(Index)
			end
		end
		class DomainAddDefaultRecords < R '/domain/([^/]+)/add-default-records'
			def get(domain)
				@domain = Domain.find(:first, :conditions => ['name = ?', domain])
				render :domainadddefaultrecords
			end
			def post(domain)
				@domain = Domain.find(:first, :conditions => ['name = ?', domain])
				delegation = [
					['.', 'SOA', 'ns1.theinternetco.net. hostmaster.theinternetco.net. 1 3600 3600 2419200 3600'],
					['.', 'NS', 'ns1.theinternetco.net'], 
					['.', 'NS', 'ns2.theinternetco.net']
				]
				records = if @input.records == 'Default'
					[
						['.', 'A', '209.97.235.99'], 
						['.', 'MX', 'host.theinternetco.net', 10], 
						['www', 'CNAME', '.'], 
						['mail', 'CNAME', 'host.theinternetco.net']
					]
				elsif @input.records == 'Google'
					[
						['.', 'A', '209.97.235.98'],
						['.', 'MX', 'ASPMX.L.GOOGLE.COM', 10],
						['.', 'MX', 'ALT1.ASPMX.L.GOOGLE.COM', 20],
						['.', 'MX', 'ALT2.ASPMX.L.GOOGLE.COM', 20],
						['.', 'MX', 'ASPMX2.GOOGLEMAIL.COM', 30],
						['.', 'MX', 'ASPMX3.GOOGLEMAIL.COM', 30],
						['.', 'MX', 'ASPMX4.GOOGLEMAIL.COM', 30],
						['docs', 'CNAME', 'ghs.google.com'],
						['mail', 'CNAME', 'ghs.google.com'],
						['calendar', 'CNAME', 'ghs.google.com']
					]
				elsif @input.records == 'Intelect'
					[
						['.', 'MX', 'host.theinternetco.net', 10],
						['mail', 'CNAME', 'host.theinternetco.net'],
						['pop', 'CNAME', 'host.theinternetco.net'],
						['imap', 'CNAME', 'host.theinternetco.net'],
						['smtp', 'CNAME', 'host.theinternetco.net'],
						['webmail', 'CNAME', 'host.theinternetco.net']
					]
				else
					raise 'Invalid record set'
				end
				(delegation + records).each do |rec|
					r = @domain.records.new
					r.name = if rec[0] == '.' then @domain.name else [rec[0], @domain.name].join('.') end
					r.type = rec[1]
					r.content = if rec[2] == '.' then @domain.name else rec[2] end
					r.prio = rec[3]
					r.ttl = 3600
					r.save!
				end
				redirect R(DomainOverview, @domain.name)
			end
		end

		class DomainRecordDelete < R '/domain/([^/]+)/record/(\d+)/delete'
			def get(domain, r)
				@record = Record.find(r.to_i)
				render :domainrecorddelete
			end
			def post(domain,r)
				@record = Record.find(r.to_i)
				@record.destroy
				redirect R(DomainOverview, domain)
			end
		end

		class DomainRecordEdit < R '/domain/([^/]+)/record/(\d+|new)'
			def get(domain, r)
				if r == 'new'
					@domain = Domain.find(:first, :conditions => ['name = ?', domain])
					@record = Record.new
					@record.domain = @domain
				else
					@record = Record.find(r.to_i)
				end
				if !@record
					render :domainrecordcreate
				else
					render :domainrecordedit
				end
			end
			def post(domain, r)
				if r == 'new'
					@domain = Domain.find(:first, :conditions => ['name = ?', domain])
					@record = Record.new
					@record.domain = @domain
				else
					@record = Record.find(r.to_i)
					@domain = @record.domain
				end
				if @input.name == '.' or @input.name == ''
					@input.name = @domain.name
				else
					if !@input.name.ends_with? ".#{@domain.name}" and @input.name != @domain.name
						@input.name += ".#{@domain.name}"
					end
				end
				["name", "content", "comments", "type", "ttl", "prio"].each do |e|
					@record[e] = @input[e]
				end
				@record.save!
				if @record[:type] != 'SOA'
					soa = @domain.records.select { |r| r.type = 'SOA' }.first
					soafields = soa.content.split(' ')
					soafields[2] = Integer(soafields[2]) + 1
					soa.content = soafields.join(' ')
					soa.save!
				end
				redirect R(DomainOverview, @record.domain.name)
			end
		end

		class DomainCreate < R '/domain/new'
			def get
				render :domaincreate
			end

			def post
				Domain.create(:name => @input.name, :type => 'MASTER')
				redirect R(DomainOverview, @input.name)
			end
		end

		class DomainFinder < R '/domain'
			def get
				if @input.q
					redirect R(DomainOverview, @input.q)
				else
					redirect R(Index)
				end
			end
		end

		class DomainOverview < R '/domain/([^/]+)'
			def get(dom)	
				@domain = Domain.find(:first, :conditions => [ 'name = ?', dom ])
				if !@domain
					@dom = dom
					render :domainrecordcreate
				else
					render :domainoverview
				end
			end
		end

		class EmployeeList < R '/employees'
			def get
				@employees = Employee.find(:all, :order => 'name')
				render :employeelist
			end
		end

		class EmployeeView < R '/employees/(\d+)'
			def get(id)
				@employee = Employee.find(id.to_i)
				render :employeeview
			end
		end

		class GroupPages < R('/g','/g/(\d+|new)','/g/(\d+)/(\w+)')
			def get(gid=nil,opt=nil)
				if gid.nil? or gid.empty?
					page = input['page'] or 1
					groups = Group.find(:all, :limit =>30*page, :offset =>30*(page-1), :order =>'gid')
					if groups.nil? or groups.empty?
						render :group_notfound
					else
						@content = "<a href='%s'>Create Group</a>" % [self/R(GroupPages,'new')]
						@list = [['Name','Users','Members']]
						@list += groups.map{|g|[
							"<a href='%s'>%s</a>" % [self/R(GroupPages,g.gid), g.name],
							g.users.size,
							g.members.size
						]}
						render :userlist
					end
				elsif gid == 'new'
					render :group_create
				else
					group = Group.find(gid) rescue nil
					if group.nil? then render :group_notfound; else
						if opt.nil? or opt.empty?
							@group = group; render :group
						else case opt
							when 'name'
								@list_action = R(GroupPages, group.gid, opt)
								@list = [["Enter value for #{group.gid}(#{group.name})'s #{opt}"]]
								@list += [["<input type='text' name='#{opt}' />"]]
								@list += [["<input type='submit' value='Alter' />"]]
								render :userlist
						end end
					end
				end
			end

			def post(gid=nil,opt=nil)
				if gid.nil? or gid.empty?
					render :wtf
				elsif gid == 'new'
					unless input['name'].nil?
						opts = {:name => input['name']}
						opts[:gid] = input['gid'][/\d+/].to_i unless input['gid'].nil? or input['gid'].empty?
						opts[:passwd] = input['passwd'] unless input['passwd'].nil? or input['passwd'].empty?
						group = Group.create(opts)
						redirect GroupPages, group.gid
					else @content = 'No name provided'; render :index; end
				else
					group = Group.find(gid) rescue nil
					if group.nil? then render :group_notfound; else
						case opt
						when 'name'
							value = input[opt]
							unless value.nil? or value.empty?
								group.update_attribute(opt,value)
								redirect GroupPages, group.gid
							else @content = "Bad value. #{value.inspect}"; render :index; end
						end
					end
				end
			end
		end

		class Index < R '/'
			def get
				@active_calls = Call.find(:all, :conditions => "status = 'Start'", :order => 'event_date_time')
				@open_invoices = Invoice.find(:all, :conditions => "status = 'Open'", :order => 'id')
				render :index
			end
		end

		class InvoicesSendUnsent < R '/send_invoices'
			def	get
				@ninvoices = Elf::Invoice.where(:status => 'Closed').includes(:history_items).where('invoice_history_items.id IS NULL').count()
				render :invoicessendunsent
			end
			def post
				@results = []
				@all = []
				Elf::Invoice.where(:status => 'Closed').includes(:history_items).where('invoice_history_items.id IS NULL').each do |i|
					@all << i
					@results << i.send_by_email(:message => @input.message) if !i.sent?
				end
				render :invoicessent
			end
		end


		class InvoiceDeleteItem < R '/customers/(\d+|[^/]+)/invoices/(\d+|new)/(\d+|new)/delete'
			def get(customer, invoice, item)
				@contact = getcontact(customer)
				@invoice = cache(Invoice, customer, invoice)
				@item = @invoice.items[item.to_i]
				render :invoiceitemdeleteconfirm
			end
			def post(customer, invoice, item)
				@contact = getcontact(customer)
				@invoice = cache(Invoice, customer, invoice)
				@item = @invoice.items[item.to_i]
				@item.destroy
				@invoice.items.delete @item
				redirect R(InvoiceEdit, @contact.id, invoice)
			end
		end

		class InvoiceEditItem < R '/customers/(\d+|[^/]+)/invoices/(\d+|new)/(\d+|new)'
			def get(customer, invoice, item)
				@contact = getcontact(customer)
				@invoice = cache(Invoice, customer, invoice)
				if item == 'new'
					@item = InvoiceItem.new
				else
					@item = @invoice.items[Integer(item)]
				end
				render :invoiceedititem
			end
			def post(customer, invoice, item)
				@contact = getcontact(customer)
				@invoice = cache(Invoice, customer, invoice)
				if item == 'new'
					@item = InvoiceItem.new
				else
					@item = @invoice.items[Integer(item)]
				end
				@item.quantity = @input.qty || 1
				@item.description = @input.desc
				@item.amount = Money.new(@input.amount.to_f * 100, 'USD')
				if !@invoice.items.index(@item) and @item
					@invoice.items << @item
				end
				redirect R(InvoiceEdit, @contact.id, @invoice.id || 'new')
				
			end
		end

		class InvoiceEdit < R '/customers/(\d+|[^/]+)/invoices/(\d+|new)'
			def get(customer, invoice)
				@contact = getcontact(customer)
				@invoice = cache(Invoice, customer, invoice)
				@invoice.account ||= @contact.accounts.first
				render :invoiceedit
			end
			def post(customer, invoice)
				@contact = getcontact(customer)
				@invoice = cache(Invoice, customer, invoice)
				@invoice.memo = @input.memo
				@invoice.duedate = @input.duedate
				@invoice.job = @input.job
				case @input.command
				when /Cancel/
					$cache.delete cachekey(Invoice, customer, invoice)
				when /Close/
					raise "Invoice already closed" if @invoice.closed?
					@invoice.save!
					@invoice.close
					$cache.delete cachekey(Invoice, customer, invoice)
				when /Email/
					@invoice.send_by_email
				when /Delete/
					raise "Invoice already closed" if @invoice.closed?
					@invoice.destroy
					$cache.delete cachekey(Invoice, customer, invoice)
				when /Save/
					raise "Invoice already closed" if @invoice.closed?
					@invoice.date ||= Date.today
					@invoice.account ||= @contact.accounts.first
					@invoice.save!
					@invoice.invoice_items.each  do |i|
						i.save!
					end
					$cache.delete cachekey(Invoice, customer, invoice)
				else
					raise 'Invalid action'
				end
				redirect R(CustomerOverview, @contact.id)
			end
		end

		class LoginPages < R('/l','/l/(.+)')
			# Mostly non function, a gate to UserPages
			def get(lid=nil)
				logins = if lid.nil? or lid.empty?
						page = input['page'] or 1
						Login.find(:all, :limit =>30*page, :offset =>30*(page-1), :order =>'id')
					else
						Login.find(:all, :order => 'id', :conditions => ['login ~ ?', lid])
					end
				if logins.nil? or logins.empty?
					render :login_notfound
				else
					@list = [['Login','User']]
					@list += logins.map{|l|[
						"<a href='%s'>%s</a>" % [self/R(LoginPages,"^#{l.login}$"), l.login],
						"<a href='%s'>%s</a>" % [self/R(UserPages,l.uid), if l.user.gecos.empty? then l.login else l.user.gecos end]
					]}
					render :userlist
				end
			end
		end

		class NewPayment < R '/payment/new_for_account/(\d+)'
			def get(account)
				@account_id = account.to_i
				render :newpayment
			end

			def post(account)
				@account = Elf::Company.find(1).accounts.find(account.to_i)
				payment = Payment.new
				payment.date = @input.date
				payment.amount = Money.new(BigDecimal.new(@input.amount) * 100)
				payment.fromaccount = account.to_i
				payment.number = @input.number
				payment.validate
				payment.save
				redirect R(CustomerOverview, @account.contact.id)
			end
		end

		class NoteCreate < R '/customers/(\d+|[^/]+)/notes/new'
			def get(id)
				@contact = getcontact(id)
				@page_title = 'Create note for ' + @contact.account_name
				render :notecreate
			end

			def post(id)
				@contact = getcontact(id)
				@contact.notes << Elf::Note.new(:note => @input.note, :mtime => Time.now)
				@contact.save
				redirect R(NoteView, @contact.id)
			end
		end

		class NoteView < R '/customers/(\d+|[^/]+)/notes'
			def get(id)
				@contact = getcontact(id)
				@page_title = 'Notes for ' + @contact.account_name
				render :noteview
			end
		end

		class OnlineUsers < R '/online-users'
			def get
				@active_calls = Call.find(:all, :conditions => "status = 'Start'", :order => 'event_date_time')
				render :online_users
			end
		end

		class ServiceFinder < R '/services/find'
			def get
				search = @input.q
				@contact = Elf::Models::Service.find(:all, :conditions => ["detail ilike ?", "%#{@input.q}%"], :order => 'detail')
				@contact = @contact.map { |s| s.contact }.uniq
				render :customerwithservicelist
			end
		end
		
		class ServiceBill < R '/services/(\d+)/bill'
			def get(id)
				@service = Elf::Service.find(id.to_i)
				render :servicebill
			end

			def post(id)
				@service = Elf::Service.find(id.to_i)
				times = begin
					Integer(@input.times)
				rescue
					1
				end
				invoice = Elf::Invoice.new
				invoice.account = @service.contact.account
				invoice.add_from_service(@service, times)
				@service.nextbilling = case @service.period
				when 'Annually'
					@service.nextbilling >> (12 * times)
				when 'Monthly'
					@service.nextbilling >> (1 * times)
				else
					raise "Unknown billing period"
				end
				if(input.discount and !input.discount.strip.empty?)
					total = invoice.amount
					discount = case input.discount
					when /^(\d+)%$/
						total * (Integer($1) / 100.0)
					when /^(\d+|\d+[.]\d{2})$/
						discount = Float($1)
					else
						raise "Bad discount"
					end
					invoice.items.build(quantity: 1, description: "Discount: #{input.discount}", amount: discount * -1)
				end
				@service.save!
				invoice.save!
				invoice.close
				redirect R(CustomerOverview, @service.contact.id)
			end
		end

		class ServiceEnd < R '/services/(\d+)/end'
			def get(id)
				@service = Elf::Service.find(id.to_i)
				render :serviceend
			end
			def post(id)
				@service = Elf::Service.find(id.to_i)
				@service.end_on(Date.parse(@input.date))
				redirect R(CustomerOverview, @service.contact.id)
			end
		end

		class Style < R '/(.*\.css)'
			def get(file)
				@headers['Content-Type'] = 'text/css'
				File.read(File.join(File.dirname(__FILE__), file))
			end
		end

		class UsersMain < R('/users')
			def get
				render :usersmain
			end
			def post
				if input.key?('type') and not input['type'].empty? then 
					case input['type']
						when 'u' then redirect UserPages, input['value']
						when 'g' then redirect GroupPages, input['value']
						when 'l' then redirect LoginPages, input['value']
						else redirect Index 
					end
				end
			end
		end

		class UserPages < R('/u','/u/(\d+|new)','/u/(\d+)/(\w+)')
			def get(uid=nil,opt=nil)
				if uid.nil? or uid.empty?
					page = input['page'] or 1
					users = User.find(:all, :limit =>30*page, :offset =>30*(page-1), :order =>'uid')
					if users.nil? or users.empty?
						render :user_notfound
					else
						@content += "<a href='%s'>Create User</a>" % [self/R(UserPages,'new')]
						@list = [['UID','Group','Logins']]
						@list += users.map{|u|[
							"<a href='%s'>%s</a>" % [self/R(UserPages,u.uid), u.gecos],
							"<a href='%s'>%s</a>" % [self/R(UserPages,u.gid), (u.group ? u.group.name : u.gid)],
							u.logins.size
						]}
						render :userlist
					end
				elsif uid == 'new'
					render :user_create
				else
					user = User.find(uid)
					if user.nil? then render :user_notfound; else
						if opt.nil? or opt.empty?
							@user = user; render :userview
						else case opt
							when 'shell','homedir','gecos','group'
								@list_action = R(UserPages, user.uid, opt)
								@list = [["Enter value for #{user.uid}(#{user.gecos})'s #{opt}"]]
								@list += [["<input type='text' name='#{opt}' />"]]
								@list += [["<input type='submit' value='Alter' />"]]
								render :userlist
						end end
					end
				end
			end
			def post(uid=nil,opt=nil)
				if uid.nil? or uid.empty?
					render :wtf
				elsif uid == 'new'
					unless input['login'].nil? or input['login'].empty?
						opts = {:gecos => input['login'], :homedir => '/home/user/'+input['login']}
						opts[:gecos] = input['gecos'] unless input['gecos'].nil? or input['gecos'].empty?
						opts[:homedir] = input['homedir'] unless input['homedir'].nil? or input['homedir'].empty?
						user = User.create(opts)
						user.logins.create(:login => input['login'])
						unless input['group'].nil? or input['group'].empty?
							groups = Group.find(:all,:conditions =>['name ~ ?', input['group']])
							if groups.size > 1
								@list_action = R(UserPages,user.uid,'gid')
								@list = [['Select group:']]
								@list += groups.map{|g|
									"<button type='submit' name='gid' value='#{g.gid}'>#{g.name}</button>"
								}
								render :userlist
							elsif groups.size == 1
								user.group = groups.first
								redirect UserPages, user.uid
							end
						else redirect UserPages, user.uid end
					else @content = 'No login provided'; render :index; end
				else
					user = User.find(uid) rescue nil
					if user.nil? then render :user_notfound; else
						case opt
						when 'groups'
							if input.key?('ngroup') and not input['ngroup'].empty?
								groups = Group.find(:all,:conditions => ['name ~ ?', input['ngroup']])
								if groups.empty?
									@content = 'No groups match.'
									render :index
								elsif groups.size == 1
									user.group_memberships.create(:gid => groups.first.gid)
									redirect UserPages, user.uid
								else
									@list_action = R(UserPages,user.uid,'groups')
									@list = [['Select group:']]
									@list += groups.map{|g|
										"<button type='submit' name='ngroup' value='#{g.name}'>#{g.name}</button>"
									}
									render :userlist
								end
							elsif input.key?('rgroup') and not input['rgroup'].empty?
								membership = user.memberships.find(:first, :conditions => ['gid = ?', input['rgroup']])
								unless membership.nil?
									if input['confirm'] == 'true'
										user.group_memberships.delete(membership)
										redirect UserPages, user.uid
									elsif input['confirm'] == 'false'
										redirect UserPages, user.uid
									else
										@list_action = R(UserPages, user.uid, 'groups')
										@content = "<input type='hidden' name='rgroup' value='#{input['rgroup']}' />"
										@list = [
											['Delete membership:',membership.group.name],
											["<button type='submit' name='confirm' value='true'>Confirm</button>","<button type='submit' name='confirm' value='false'>Deny</button>"]
										]
										render :userlist
									end
								else
									@content = 'No such membership for this user.'; render :index
								end
							else
								@content = 'No group operation provided.'; render :index
							end
						when 'logins'
							if input.key?('nlogin') and not input['nlogin'].empty?
								user.logins.create(:login => input['nlogin'])
								redirect UserPages, user.uid
							elsif input.key?('rlogin') and not input['rlogin'].empty?
								login = user.logins.find(input['rlogin'])
								unless login.nil?
									if input['confirm'] == 'true'
										Login.delete(login.id)
										redirect UserPages, user.uid
									elsif input['confirm'] == 'false'
										redirect UserPages, user.uid
									else
										@list_action = R(UserPages, user.uid, 'logins')
										@content = "<input type='hidden' name='rlogin' value='#{input['rlogin']}' />"
										@list = [
											['Delete login:',login.login],
											["<button type='submit' name='confirm' value='true'>Confirm</button>","<button type='submit' name='confirm' value='false'>Deny</button>"]
										]
										render :userlist
									end
								else
									@content = 'No such login for this user.'; render :index
								end
							else
								@content = 'No login operation provided.'; render :index
							end
						when 'group'
							unless input['group'].nil? or input['group'].empty?
								groups = Group.find(:all,:conditions =>['name ~ ?', input['group']])
								@list_action = R(UserPages,user.uid,'gid')
								@list = [['Select group:']]
								@list += groups.map{|g|
									"<button type='submit' name='gid' value='#{g.gid}'>#{g.name}</button>"
								}
								render :userlist
							else redirect UserPages, user.uid, 'group'; end
						when 'shell','homedir','gid','gecos'
							value = input[opt]
							unless value.nil? or value.empty?
								user.update_attribute(opt,value)
								redirect UserPages, user.uid
							else @content = "Bad value. #{value.inspect}"; render :index; end
						end
					end
				end
			end
		end
	end

	module Views

		def _name(a)
			if a.first or a.last
				self << "#{a.first || ''} #{a.last || ''}"
				br
			end
			if a.organization
				self << "#{a.organization}"
				br
			end
		end

		def _address(a, name = true)
			_name(a) if name
			if a.street
				self << "#{a.street}"
				br
			end
			if a.city and a.state
				self << "#{a.city}, #{a.state} "
			end
			if a.postal
				self << "#{a.postal}"
			end
		end

		def removecard
			if @contact.cardnumber or @contact.cardexpire
				#header do
					h1 "Remove #{@contact.account_name}'s card?"
				#end
				form :action => R(RemoveCard, @contact.id), :method => 'post' do
					input :type => 'submit', :value => 'Delete'
				end
			else
				#header do
					h1 "No card on file"
				#end
			end
		end

		def chargecard
			#header do
				h1 "Charge #{@contact.account_name}'s card"
			#end
			form :action => R(ChargeCard, @contact.id), :method => 'POST' do
				p do 
					label :for => 'amount' do "Amount" end
					input :type => 'text', :name => 'amount', :value => @input.amount, :size => 6
				end
				p do
					label :for => 'cardnumber' do "Card Number" end
					input :type => 'text', :name => 'cardnumber', :value => if @contact.cardnumber then "*#{@contact.cardnumber[-4..-1]}" else "" end
				end
				p do
					label :for => 'cardexpire' do "Card Expires" end
					input :type => 'text', :name => 'cardexpire', :value => if @contact.cardexpire then "#{@contact.cardexpire}" else "" end
				end
				input :type => 'submit', :value => "Charge"
			end
		end

		def cardbatchlist
			#header do
				h1 'Credit Card Batches'
			#end
			table do
				tr do
					th { 'Id' }
					th { 'Date' }
					th { 'Status' }
				end
				@batches.each do |batch|
					tr do
						td { batch.id }
						td { a(batch.date.strftime('%Y/%m/%d %H:%M'), :href => R(CardBatchView, batch.id)) }
						td { batch.status }
					end
				end
			end
		end

		def cardbatchview
			#header do
				h1 "Card Batch \##{@batch.id}"
			#end
			p do
				success = @batch.items.select { |i| i.status == 'Completed' }
				"#{success.size} completed successfully, total of #{success.inject(Money.new(0)) { |a,e| a += e.amount}}"
			end
			failures = @batch.items.reject { |i| i.status == 'Completed' }
			table do
				tr do
					th { 'Account' }
					th { 'Name' }
					th { 'Card' }
					if @batch.status == 'In Progress'
						th { 'Amount' }
					else 
						th { 'Failure' }
					end
				end
				failures.each do |item|
					tr do
						td { a(item.name, :href => R(CustomerOverview, item.contact.id)) }
						td { text(item.contact.account_name) }
						td { "*#{item.cardnumber[-4..-1]}, #{item.cardexpire.strftime('%Y/%m')}" }
						td do
							if item.status == 'Error' or item.status == 'Invalid'
								item.message
							elsif !item.status
								item.amount
							else
								"#{item.status}#{if item.cardexpire < Date.parse(batch.date.strftime('%Y/%m/%d')) then ': Card Expired' end}"
							end
						end
						td do
							a('Again', :href => R(ChargeCard, item.contact.id, :amount => item.amount))
						end
					end
				end
			end
			if @batch.status == 'In Progress'
				form :action => R(CardBatchSend, @batch.id), :method => 'post' do
					input :type => 'submit', :value => 'Send Batch'
				end
			end
		end

		def cardexpirationlist
			table do
				tr do 
					th { 'Customer' }
					th { 'Expires' }
					th { 'Balance' }
					th { 'Services' }
				end
						
				@contact.each do |c|
					tr do 
						td { a(c.account_name, :href => R(CustomerOverview, c.id)) }
						td { c.cardexpire.strftime('%Y/%m/%d') }
						td { "$#{c.account.balance}" }
						td { "#{c.active_services.length} #{c.active_services.length == 1?'service':'services'}" }
					end
				end
			end
		end

		def customeraddphone
			form :action => R(CustomerAddPhone, @contact.id), :method => 'post' do
				p do
					label :for => :phone do "Phone:" end
					input :name => :phone
				end
				p do
					label :for => :which do "Which phone is this?" end
					input :name => :which
				end
				input :type => 'submit', :value => 'Add'
			end
		end

		def customerupdatecc
			form :action => R(CustomerUpdateCC, @contact.id), :method => 'post' do
				p do
					label :for => :newcc do "New Credit card number:" end
					input :name => :newcc
				end
				p do
					label :for => :newexp do "Expiration:" end
					input :name => :newexp
				end
				input :type => :submit, :value => 'Update'
			end
		end

		def _contact(contact)
			p.address do
				_name(contact)
				if contact.has_address?
					_address(contact, false)
				end
			end
		end

		def customeroverview
			p { a(@contact.emailto, :href => 'mailto:' + @contact.emailto) }

			_contact(@contact)

			ph = @contact.phones.reject { |p| p.obsolete }
			if !ph.empty?
				h3 "Phone numbers"
				ul.phones do
					ph.each do |phone|
						li { a(phone.phone, :href=> 'tel:' + phone.phone.gsub(/[^+0-9]/, '')); self << " #{phone.which}" }
					end
				end
			end
			p do 
				a('Add Phone', :href => R(CustomerAddPhone, @contact.id))
			end

			p do
				@contact.contact_account_relations.each do |rel|
					account = rel.account
					p do 
						text("#{rel.relation} ") if rel.relation
						text("Account ##{account.id} Balance: $#{account.balance}. ")
						pmt = account.debits.last rescue nil
						text("Last payment No. #{pmt.number || 'none'}, $#{pmt.amount * -1} on #{pmt.txn.date.strftime('%Y/%m/%d')}") if pmt

						if account.balance > Money.new(0)
							text ' '
							a('Charge Card', :href => R(ChargeCard, @contact.id, {'amount' => account.balance}))
						end
						if !account.open_invoices.empty?
							text ' '
							open_invoices = account.open_invoices
							a("#{open_invoices.size} open invoice#{open_invoices.size == 1 ? "s" : ""}", :href => R(AccountHistory, @contact.id, :status => 'Open'))
							self << ", total $#{open_invoices.inject(Money.new(0)) { |a,e| a += e.amount }}"
						end
						if !account.invoices.empty?
							a("Billing History", :href=>R(AccountHistory, @contact.id, account.id))
							text ' '
						end
						a("Record Payment", :href=> R(NewPayment, account.id))
						text ' '
						a('Credit Account', :href=> R(AccountCredit, account.id))
						text ' '
					end
				end
			end
			if @contact.cardnumber
				p do
					text "Bills to #{case @contact.cardnumber[0,1]; when '4' then "Visa"; when '5' then 'Mastercard'; when '3' then "American Express"; else "Card"; end} ending *#{@contact.cardnumber.strip[-4..-1]}, expires #{@contact.cardexpire.strftime('%Y/%m')}"
					text ' '
					a('Remove', :href => R(RemoveCard, @contact.id))
				end
			end

			unless @contact.active_services.empty?
				h2 'Services'
				table do
					@contact.services.find(:all, :conditions => 'dependent_on IS NULL and (ends is null or ends > now())').each do |s|
					_service(s)
					end
				end
			end

			if !@contact.purchase_order_items.select { |p| !p.received? or p.received> Date.today - 7 }.empty?
				h2 "Purchases"
				table do
					tr do
						th { "Date" }
						th.numeric { "Qty" }
						th { "Description" }
						th { 'Date Received' }
					end
					@contact.purchase_order_items.each do |p|
						tr do
							td { p.purchase_order.date }
							td.numeric { p.quantity }
							td { p.description }
							td { if p.received then p.received.strftime('%Y/%m/%d') else "Not yet" end }
						end
					end
				end
			end

			p.screen do
				a('Create Invoice', :href=> R(InvoiceEdit, @contact.id, 'new'))
				text ' '
				a('New Service', :href=> R(CustomerServiceNew, @contact.id))
				text ' '
				a('Notes', :href=> R(NoteView, @contact.id))
				text ' '
				a('Edit Record', :href=> R(ContactEdit, @contact.id))
				text ' '
				a('Update CC #', :href=> R(CustomerUpdateCC, @contact.id))
			end
				
		end

		def _service(s, level = 0)
			if !s.ends or s.ends >= Date.today
				tr do
					td do
						text('&nbsp;' * 4 * level)
						if ['DNS', 'Domain Registration', 'Domain Hosting'].include? s.service
							text(s.service + ' for ');
							a(s.detail || '', :href => R(DomainOverview, s.detail))
						elsif ['Email', 'Shell Access'].include? s.service
							text(s.service + ' for ')
							a(s.detail || '', :href => R(LoginPages, s.detail))
						else
							text(s.service + " for " + (s.detail || ''))
						end
						if s.dsl_info
							small {  " #{s.dsl_info.ihost}  #{s.dsl_info.speed}" }
						end
					end
					td "$#{s.amount}"
					td do
						"#{s.period.downcase} each #{if s.period == 'Monthly' then "#{s.starts.day} of the month" else s.starts.strftime('%B %e') end}"
					end
					td do
						if s.starts > Date.today then text(" starts #{s.starts}") end
						if s.ends then text(" ends #{s.ends}") end
					end
					td do
						a('End', :href=> R(ServiceEnd, s.id))
						text ' '
						a('Bill', :href => R(ServiceBill, s.id))
					end
				end
				if !s.dependent_services.empty?
					s.dependent_services.each do |dep|
						_service(dep, level + 1)
					end
				end
			end
		end

		def contactedit
			form :action => R(ContactEdit, @contact.id || 'new'), :method => 'post' do
				table do
					tr do
						td { label(:for => 'name') { 'Name ' } }
						td { input :name => 'name', :value => @contact.name } 
					end
					tr do
						td { label(:for => 'first') { 'First' } }
						td { input :name => 'first', :value => @contact.first } 
					end
					tr do
						td { label(:for => 'last') { 'Last' } }
						td { input :name => 'last', :value => @contact.last } 
					end
					tr do
						td { label(:for => 'organization') { 'Organization' } }
						td { input :name => 'organization', :value => @contact.organization } 
					end
					tr do
						td { label(:for => 'emailto') { 'Email' } }
						td { input :name => 'emailto', :value => @contact.emailto } 
					end
					tr do
						td { label(:for => 'street') { 'Street' } }
						td { input :name => 'street', :value => @contact.street } 
					end
					tr do
						td { label(:for => 'street2') { 'Street 2' } }
						td { input :name => 'street2', :value => @contact.street2 } 
					end
					tr do
						td { label(:for => 'city') { 'City' } }
						td { input :name => 'city', :value => @contact.city } 
					end
					tr do
						td { label(:for => 'state') { 'State' } }
						td { input :name => 'state', :value => @contact.state } 
					end
					tr do
						td { label(:for => 'postal') { 'Postal' } }
						td { input :name => 'postal', :value => @contact.postal } 
					end
					tr do
						td { label(:for => 'country') { 'Country' } }
						td { input :name => 'country', :value => @contact.country, :size => 2 } 
					end
					tr do
						td { }
						td { input :type => 'submit', :value => 'Save' }
					end
				end
			end
		end

		def customerlist(which = :customeractions)
			ul do 
				@contacts.each do |e|
					li do
						a(e.name || '(no name)', :href=> R(CustomerOverview, e.id))
						text(" #{e.first} #{e.last} #{e.organization} ") 
						send(which, e)
					end
				end
				li { a('Add customer', :href => R(ContactEdit, 'new')) }
			end
		end

		def customeractions(e)
			a('Record Payment', :href=> R(NewPayment, e.accounts.first.id))
			text ' '
			a("Create invoice", :href=> R(InvoiceEdit, e.id, 'new'))
		end

		def customerhighbalances(customer)
			self << "$#{contact.account.balance}; #{contact.active_services.length} service(s)"
		end

		def customerwithservicelist
			#header do
				h1 "Customers with services matching \"#{@input.q}\""
			#end
			ul do 
				@contacts.each do |e|
					li do
						a(e.name, :href=> R(CustomerOverview, e.id))
						text(" #{e.first} #{e.last} #{e.organization} ") 
						a('Record Payment', :href=> R(NewPayment, e.account.id))
						ul do
							e.services.select { |s| (s.detail || '').include? @input.q }.each do |s|
								li { s.service + ' ' + s.detail + (if s.ends then " end #{s.ends.strftime('%Y/%m/%d')}" else '' end)}
							end
						end
					end
				end
			end
		end

		def customerservicenew
			#header do
				h1 'Add service'
			#end
			form :action => R(CustomerServiceNew, @contact.id), :method => 'post' do
				table do
					tr { th "Service"; td { input :name => 'service' } }
					tr { th "Detail"; td { input :name => 'detail' } }
					tr { th "Amount"; td { input :name => 'amount' } }
					tr { th "Period"; td { select :name => 'period' do option 'Monthly'; option 'Annually' end } }
					tr { th "Starting"; td { input :name => 'starts', :value => 'Now' } }
				end
				input :type => 'submit', :value => 'Add'
			end
		end

		def domaindeleteconfirm
			#header do
				h1 "Delete #{@domain.name}?"
			#end
			form :action => R(DomainDelete, @domain.name),  :method => 'post' do
				input :type => 'submit', :value => "Delete"
			end
		end

		def domainadddefaultrecords
			#header do
				h1 'Add default records'
			#end
			form :action => R(DomainAddDefaultRecords, @domain.name), :method => 'post' do
				select :name => 'records' do
					option 'Default'
					option 'Google'
					option 'Intelect'
				end
				p "Add default records to #{@domain.name}?"
				input :type => 'submit', :value => 'Add'
			end
		end

		def domaincreate
			#header do
				h1 'create domain'
			#end
			form :action => R(DomainCreate), :method => 'post' do
				label :for => 'name' do "Name" end
				input :name => 'name', :id => 'name', :type => 'text'
				input :type => 'submit', :value => 'Create'
			end
		end

		def domainrecordcreate
			form :action => R(DomainCreate), :method => 'post' do
				p "The domain was not found. Create it?"
				input :type => 'hidden', :name => 'name', :id => 'name', :value => @dom
				input :type => 'submit', :value => 'Create'
			end
		end

		def domainrecorddelete
			#header do
				h1 "Record for #{@record.domain.name}"
			#end
			form :action => R(DomainRecordDelete, @record.domain.name, @record.id), :method => 'post' do
				p "Are you sure you want to delete this record?"
				input :type => 'submit', :value => 'delete'
			end
		end
				

		def domainrecordedit
			#header do
				h1 "Record for #{@record.domain.name}"
			#end
			form :action => R(DomainRecordEdit, @record.domain.name, @record.id || 'new'), :method => 'post' do
				table do
					tr do
						th 'Name'
						td { input :type => 'text', :name => 'name', :value => @record.name }
					end
					tr do
						th 'Type'
						td do
							select :name => 'type' do
								['A', 'SOA', 'MX', 'AAAA', 'CNAME', 'TXT', 'SRV', 'PTR', 'NS'].each do |e|
									if @record[:type] == e
										option(:selected=>'selected') { e }
									else
										option e
									end
								end
							end
						end
					end
					tr do
						th 'TTL'
						td { input :type => 'text', :size=>3, :name => 'ttl', :value => @record.ttl || '3600' }
					end
					tr do
						th 'Priority'
						td { input :type => 'text', :size=>3, :name => 'prio', :value => @record.prio }
					end
					tr do
						th 'Content'
						td { input :type => 'text', :name => 'content', :value => @record.content }
					end
					tr do
						th 'Comments'
						td { textarea :name => 'comments' do @record.comments end }
					end


					tr do
						th ''
						td { input :type => 'submit', :value => 'Save' }
					end
				end
			end
		end

		def domainoverview
			#header do
				h1 "Domain #{@domain.name}"
			#end
			table do
				tr do 
					th 'Name'
					th 'TTL'
					th 'Type'
					th 'Content'
				end
				@domain.records.sort_by(&:sortkey).each do |r|
					tr do
						td(if r.name == r.domain.name then '.' else r.name.gsub(".#{r.domain.name}", '') end)
						td.numeric r.ttl
						td r[:type]
						td do
							self << "#{(r.prio.to_s || '')} "
							r.content.gsub(/.{40}/, "\\0\0").split("\0").each do |l|
								self << l
								br
							end
						end

						td.screen do
							a('Edit', :href=>R(DomainRecordEdit, r.domain.name, r.id))
							text ' '
							a('Delete', :href=>R(DomainRecordDelete, r.domain.name, r.id))
						end
					end
				end
			end
			p.screen do
				a('Add Record', :href=>R(DomainRecordEdit, @domain.name, 'new'))
				text ' '
				a('Delete Domain', :href=>R(DomainDelete, @domain.name))
				if @domain.records.empty?
					text ' '
					a('Add default records', :href => R(DomainAddDefaultRecords, @domain.name))
				end
			end
		end

		def employeelist
			#header do
				h1 'Employees'
			#end
			ul do
				@employees.each do |e|
					li { a(e.name, :href => R(EmployeeView, e.id)) }
				end
			end
		end

		def employeeview
			#header do
				h1 "Employee #{@employee.name}"
			#end
			p "Tax ID: #{@employee.taxid}"
			h2 'Recent paychecks'
			table do
				tr do
					th { 'Date' }
					th { 'Amount' }
					th { 'Withheld' }
					th { 'Net' }
					th { 'Taxes' }
				end
				@employee.paychecks(:limit => 4, :order => 'id DESC').each do |c|
					tr do
					 	td { c.check.transaction.date.strftime('%Y/%m/%d') }
						td do
						 	gross = c.check.transaction.items.select { |i| i.account.description == 'Gross Wages Payable' }.first # FIXME
							if gross then gross.amount else "Unknown" end	
						end
						td { c.check.transaction.items.select { |i| i.account.account_group == "Payable" and i.account.description != 'Gross Wages Payable' }.map { |i| i.amount }.inject(Money.new(0)) { |a,e| a + e } } # FIXME
						td { c.check.amount  * -1 }
						td { if c.taxes then c.taxes.items.select { |i| i.amount > Money.new(0) }.map {|i| i.amount }.inject(Money.new(0)) { |a,e| a + e } else '' end }
				 	end
				end
			end
		end

		def group_create
			form(:action => R(GroupPages, 'new'), :method => 'post'){
				div { text 'Name: '; input :type => 'text', :name => 'name' }
				div { input :type=> 'submit', :value => 'Create' }
			}
		end

		def group_notfound
			p 'Group not found.'
		end

		def group
			h1 { text "#{@group.gid}: "; a @group.name, :href => R(GroupPages,@group.gid,'name'); }
			div "#{@group.users.size} users."
			table.users.users! { 
				users = @group.users.to_a
				users.each_slice(5) {|s|
					tr { s.each{|u| td { 
						"<a href='%s'>%s</a>" % [self/R(UserPages,u.uid), u.gecos]
					} } }
				}
			}
			div "#{@group.members.size} members."
			table.users.members! { 
				members = @group.members.to_a
				members.each_slice(5) {|s|
					tr { s.each{|u| td { 
						"<a href='%s'>%s</a>" % [self/R(UserPages,u.uid), u.gecos]
					} } }
				}
			}
		end

		def wtf
			p 'Oh crap... Please notify webmaster.'
		end

		def index
			#header do
				h1 'Accounting'
			#end
			form :action => R(CustomerList), :method => 'GET' do
				label do
					self << 'Customers'
					input :name => 'q', :type => 'text'
				end
				input :type => 'submit', :value => 'Find'
			end

			form :action => R(ServiceFinder), :method => 'GET' do
				label do
					self << 'Services'
					input :name => 'q', :type => 'text'
				end
				input :type => 'submit', :value => 'Find'
			end

			form :action => R(VendorFinder), :method => 'GET' do
				label do
					self << 'Vendors'
					input :name => 'q', :type => 'text'
				end
				input :type => 'submit', :value => 'Find'
			end

			p do
				self << "There are "
				a("#{@open_invoices.size} invoices open", :href => R(OpenInvoices))
			end

			p do
				a('Accounts', :href=> R(AccountGroups))
				text ' '
				a('Send Invoices', :href => R(InvoicesSendUnsent))
				text ' '
				a('Credit Card Batches', :href=> R(CardBatchList))
				text ' '
				a('High Balances', :href => R(CustomerBalanceAndServiceList))
				text ' '
				a('Credit Card Expirations', :href => R(CardExpirationList))
				text ' '
				a('Record Deposit', :href => R(DepositRecord))
				text ' '
				a('Authorize.net', :href => 'https://account.authorize.net/')
			end

			h1 'Domains'

			form :action => R(DomainFinder), :method => 'GET' do
				label do
					self << 'Find'
					input :name => 'q', :type => 'text'
				end
				input :type => 'submit', :value => 'Find'
			end

			p do
				a('OpenSRS', :href=>'https://rr-n1-tor.opensrs.net/resellers/index')
			end

			h1 'Stats'
			p do
				self << "There are "
				a("#{@active_calls.size} users online", :href => R(OnlineUsers))
			end

		end

		def invoiceitemdeleteconfirm
			h1 'Delete item?'
			form :action => R(InvoiceDeleteItem, @contact.id, @invoice.id || 'new', @invoice.items.index(@item)), :method => 'post' do
				p "Quantity: #{@item.quantity}"
				p "Description: #{@item.description}"
				p "Amount: #{@item.amount}"
				input :type => 'submit', :value => 'Delete'
			end
		end

		def invoiceedit
			if !@invoice.id
				h1 'Edit new invoice'
			else
				h1 { text("Invoice \##{@invoice.id}"); span.screen { " (#{@invoice.status || 'New'})" } }
			end
			div.print do
				p.address do _address(Models::OurAddress) end
				p.address do
					_address(@invoice.account.contact) if @invoice.account.contact.has_address?
				end
			end
			if @invoice.startdate and @invoice.enddate
				p "Invoice period: #{@invoice.startdate.strftime("%Y/%m/%d")} to #{@invoice.enddate.strftime("%Y/%m/%d")}"
			else
				p "Invoice date: #{@invoice.date.strftime("%Y/%m/%d")}"
			end
			form :method => 'post', :action => R(InvoiceEdit, @contact.id, @invoice.id || 'new') do
				if @invoice.status == 'Open'
					table do
						tr do
							th "Job"
							td do input :name => 'job', :value => @invoice.job end
						end
						tr do
							th "Memo"
							td { textarea :name => 'memo' do @invoice.memo end }
						end
						tr do
							th "Due By"
							td { input :name => 'duedate' , :value => @invoice.duedate }
						end
					end
				else
					table do
						tr do
							th "Job"
							td @invoice.job
						end
						tr do
							th "Memo"
							td @invoice.memo
						end
						tr do
							th "Due By"
							td @invoice.duedate
						end
					end
				end
				table do
					tr do
						th 'Qty'
						th 'Description'
						th 'Amount'
						th 'Total'
					end
					@invoice.items.each do |i|
						tr do
							td.numeric i.quantity
							td i.description
							td.numeric i.amount
							td.numeric i.amount * i.quantity
							if @invoice.status == 'Open'
								td do
									a('Remove', :href => R(InvoiceDeleteItem, @contact.id, @invoice.id || 'new', @invoice.items.index(i) || 'new'))
									text ' '
									a('Edit', :href => R(InvoiceEditItem, @contact.id, @invoice.id || 'new', @invoice.items.index(i) || 'new'))
								end
							end
						end
					end
					tr do
						th(:colspan => 3) { "Total" }
						td.numeric @invoice.total
					end
				end
				if @invoice.status == 'Open'
					p.controls do
						a('Add item', :href => R(InvoiceEditItem, @contact.id, @invoice.id || 'new', 'new'))
					end
					p.controls do
						input :type => 'submit', :value => 'Save', :name => 'command'
						input :type => 'submit', :value => 'Cancel', :name => 'command'
						input :type => 'submit', :value => 'Close', :name => 'command'
						input :type => 'submit', :value => 'Delete', :name => 'command' if !@invoice.new_record?
					end
				else
					p.controls do
						input :type => 'submit', :value => 'Send by Email', :name => 'command'
					end
				end
			end
		end

		def invoiceedititem
			if @item.new_record?
				h1 'Add item to invoice'
			else
				h1 'Edit item on invoice'
			end
			form :action => R(InvoiceEditItem, @contact.id, @invoice.id || 'new', @invoice.items.index(@item) || 'new'), :method => 'post' do
				table do
					tr do
						th 'Qty'
						th 'Description'
						th 'Amount'
					end
					tr do
						td { input :name => 'qty', :type => 'text', :size => 4, :value => @item.quantity }
						td { input :name => 'desc', :type => 'text', :value => @item.description }
						td { input :name => 'amount', :type => 'text', :size => 4, :value => @item.amount }
					end
				end
				input :type => 'submit', :value => @item.new_record? ? 'Add' : 'Save'
			end
		end


		def invoicelist
			table do
				tr do
					th "Invoice"
					th "Date"
					th.right "Amount"
					th 'Job'
				end
				@account.open_invoices.each do |i|
					tr do
						td { a(i.id, :href => R(InvoiceEdit, @account.contact.id, i.id)) }
						td i.date.strftime('%Y/%m/%d')
						td.right i.amount
						td i.job
					end
				end
			end
		end

		def invoicessent
			h1 'Sent'
			text @all.inspect
			@results.each do |r|
				if r.respond_to? :string
					p do r.string end
				end
			end
		end

		def invoicessendunsent
			h1 'Send unsent invoices'
			form :action => R(InvoicesSendUnsent), :method => 'POST' do
				p do
					"Send #{@ninvoices} invoices"
				end
				p do
					textarea :name => 'message' do
					end
				end
				p do
					input :type => 'submit', :value => 'Send'
				end
			end
		end

		def newpayment
			h1 "Payment on account #{@account_id}"
			form :action => R(NewPayment, @account_id), :method => 'POST' do
				table do
					tr do
						th { label(:for => 'date') { "Date: " } }
						td { input :name => 'date', :id=> 'date', :type => 'text', :value => Time.now.strftime("%Y/%m/%d") }
					end
					tr do
						th { label(:for => 'amount') { "Amount: " } }
						td { input :name => 'amount', :id => 'amount', :type => 'text' }
					end
					tr do
						th { label(:for => 'number') { "Number: " } }
						td { input :name => 'number', :id => 'number', :type => 'text' }
					end
					tr do
						th { }
						td { input :type => 'submit', :value => 'Record' }
					end
				end
			end
		end

		def notecreate
			form :action => R(NoteCreate, @contact.id), :method => 'post' do
				p { textarea :name => 'note', :rows => 10, :cols => 60 do end}
				p { input :type => 'submit', :value => 'Save' }
			end
		end

		def noteview
			if @contact.notes.empty?
				p "No notes"
			else
				@contact.notes.each do |n|
					p { "#{n.mtime.strftime('%Y/%m/%d %H:%M')}:  #{n.note}" }
				end
			end
			p.screen { a('Add Note', :href=> R(NoteCreate, @contact.id)) }
		end

		def online_users
			h1 'Online users'
			table do
				thead do
					tr do
						th { "Username" }
						th { "Duration" }
						th { "Type" }
						th { "IP" }
					end
				end
				@active_calls.each do |call|
					t = (Time.now - call.event_date_time).to_i
					d = Date4::Delta.new(0,0,0,t)
					tr do
					 	td { "#{call.user_name}" }
						td { "#{if d.days > 0 then "#{d.days}d " else "" end}#{d.hours}:#{"%02i" % d.mins}:#{"%02i" % d.secs}"}
					 	td { "#{call.called_station_id.empty? ? "DSL" : "Dialup" }" }
					 	td { "#{call.framed_ip_address}" }
					end
				end
			end
		end

		def servicebill
			h1 "Bill for #{@service.service} for #{@service.detail}?"
			form :action => R(ServiceBill, @service.id), :method => 'post' do
				p do
					self << "$#{@service.amount}, #{@service.period}"
					label do
						self << " x "
						input :type => 'text', :name => 'times', :value => '1', :size => 3
					end
				end
				h3 'Discount'
				p do
					input type: 'text', name: 'discount'
				end
				p do
					input :type => 'submit', :value => 'Bill'
				end
			end
		end

		def serviceend
			h1 "End Service #{@service.service} for #{@service.detail}"
			form :action=> R(ServiceEnd, @service.id), :method => 'post' do
				input :type => 'text', :name => 'date', :value => Time.now.strftime('%Y/%m/%d')
				input :type => 'submit', :value => 'Set End Date'
			end
		end
		def _userlayout
			div.ugtitle! 'UserGroups'
			form :action => R(UsersMain), :method => 'post' do
				div.navbar! {
					input :type => 'text', :name => 'value'
					button 'Login', :type => 'submit', :name => 'type', :value => 'l'
					button 'User', :type => 'submit', :name => 'type', :value => 'u'
					button 'Group', :type => 'submit', :name => 'type', :value => 'g'
				}
			end
			hr :class => 'border'
			div.content{@content} if @content
			self << yield
		end

		def userlist
			_userlayout do
				form(:action => @list_action, :method => (@list_method or 'post')){
					div.content {@content} if @content
					table.list {
						tr { @list.shift.each{|e| th e } }
						@list.each{|item| tr { item.each{|e| td { e } } } }
					}
				}
			end
		end

		def userview
			h1.users.right { text "#{@user.gecos}"; br; small { a(
				(@user.group ? @user.group.name : " group #{@user.gid}"),
				:href => R(GroupPages,@user.gid)
			) } }
			table.users.data! {
				tr { th 'UID'; td @user.uid; }
				tr { th {a 'GID', :href =>R(UserPages,@user.uid,'group')}; td @user.gid; }
				tr { th {a 'GECOS', :href =>R(UserPages,@user.uid,'gecos')}; td @user.gecos; }
				tr { th {a 'Shell', :href =>R(UserPages,@user.uid,'shell')}; td @user.shell; }
				tr { th {a 'Home Dir', :href =>R(UserPages,@user.uid,'homedir')}; td @user.homedir; }
			}
			hr :class => 'border'
			table.users.logins! {
				tr { th 'Logins', :colspan => '2' }
				form(:action => R(UserPages, @user.uid, 'logins'), :method => 'post'){
					tr {
						td { button '+', :type => 'submit' }
						td { input :type => 'text', :name => 'nlogin', :size => '18' }
					}
				}
				form(:action => R(UserPages, @user.uid, 'logins'), :method => 'post'){
					@user.logins.each {|l| tr {
						td { button '-', :type => 'submit', :name => 'rlogin', :value => l.id.to_s }
						s = capture { a l.login, :href => R(LoginPages,"^#{l.login}$") }
						(@login.nil? or l.id != @login.id) ?
							td{s} :
							td.clogin{s}
					} } unless @user.logins.nil? or @user.logins.empty?
				}
			}
			table.users.groups! {
				tr { th 'Groups', :colspan => '2' }
				form(:action => R(UserPages, @user.uid, 'groups'), :method => 'post'){
					tr {
						td { input :type => 'text', :name => 'ngroup', :size => '18' }
						td { button '+', :type => 'submit' }
					}
				}
				form(:action => R(UserPages, @user.uid, 'groups'), :method => 'post'){
					@user.groups.each {|g| tr {
							td { a g.name, :href => R(GroupPages,g.gid) }
							td { button '-', :type => 'submit', :name => 'rgroup', :value => g.gid }
					} } unless @user.groups.nil? or @user.groups.empty?
				}
			}
		end

		def usersmain
			_userlayout do
				text @content if @content
			end
		end

		def wtf
			p 'Oh crap... wtf.'
		end

		def layout
			html5 do
				head do
					title "Elf — #{@page_title || ''}"
					link :rel => 'Stylesheet', :href=> '/site.css', :type => 'text/css'
					link :rel => 'Stylesheet', :href=> '/accounting.css', :type => 'text/css'
					script :src => 'https://ajax.googleapis.com/ajax/libs/jquery/1.4.4/jquery.min.js' do end
					script :src => 'https://ajax.googleapis.com/ajax/libs/jqueryui/1.8.7/jquery-ui.min.js' do end
					script { 'jQuery.noConflict()' }
					script :src => '/jquery.ba-bbq.js' do end
					script :src => '/accounting.js' do end
				end
				body do
					div.navigation { 
						a.controls('Back to start', :href => R(Index)) 
						form.contextdate! :action=>@env['PATH_INFO'] do
							label do
								text "Period"
								input._period!(type: 'text', value: context.period)
							end
							label do
								text "Search"
								input._q!(type: 'text', value: @input._q)
							end
							button { 'Go' }
						end

						p { self << " Logged in as #{@env['REMOTE_USER']}" }
					}
					tag!(:section) do
						h1 @page_title if @page_title
						self << yield
					end
				end
			end
		end
	end

end

require 'elf/actions'
