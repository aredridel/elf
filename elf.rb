# * Platypus imagines comments....
# <Platypus> // Fred 0.99b
# <Platypus> // A perpetually nervous man in the corner with an abacus.

# Elf. A gnarled, ancient wizardly sort, sitting in the corner, reading slips
# of paper written in an arcane script. He has no other name than simply "Elf".

$:.unshift(File.join(File.dirname(__FILE__), 'local'))

require 'camping'
Camping.goes :Elf

require 'rexml/doctype'
require 'rexml/text'
require 'amrita/template'
require 'date'
require 'uri'
require 'set'
require 'active_record'
require 'rmail'
require 'time'
require 'delegate'
require 'base64'
require 'net/smtp'
require 'elf/utility'
require 'elf/ar-fixes'
require 'active_merchant'
require 'money'

module Elf

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
		Elf::Customer.find_all.map do |c|
			begin
				i = c.generate_invoice(true, (month)..((month >> 1) - 1), 'Monthly')
				if i
					#i.send_by_email(:with_message => message)
					if c.cardnumber and c.cardexpire
						opts = {
							:amount => i.total.to_s, 
							:first => c.first, 
							:last => c.last, 
							:name => c.name, 
							:customer_id => c.id, 
							:payment_type => 'CC', 
							:transaction_type => 'AUTH_CAPTURE', 
							:cardnumber => c.cardnumber, 
							:cardexpire => c.cardexpire
						}
						if c.address
							opts.update Hash[
								:city => c.address.city, 
								:state => c.address.state, 
								:zip => c.address.zip, 
							]
						end
						batch.items << item = CardBatchItem.new(opts)
						item.charge!
					end
				end
			rescue Exception
				puts "#{$!}: #{$!.message}"
			end
			batch.save
			true
		end
	end

	module Models
	
	# An account, in the accounting sense. Balance comes later.
	class Account < Base
		def self.table_name; 'accounts'; end
		has_one :customer, :class_name => "Elf::Customer"
		has_many :entries, :class_name => 'Elf::TransactionItem', :order => 'transactions.date DESC', :include => 'transaction'
		has_many :invoices, :class_name => "Elf::Invoice", :order => 'id'
		has_many :subaccounts, :class_name => "Elf::Account", :foreign_key => 'parent'
		def self.find_all(conditions = nil, orderings = 'id', limit = nil, joins = nil)
			super
		end

		def balance
			#Transaction.find_all("account_id = '#{id}'").inject(0) { |acc,t| acc += t.amount.to_f }
			begin
				Money.new(connection.select_one(
					"SELECT SUM(amount) AS balance 
						FROM transaction_items 
							INNER JOIN accounts 
								ON (transaction_items.account_id = accounts.id)
						WHERE accounts.path like '#{path}.%' OR accounts.id = '#{id}'"
				)['balance'].to_f * 100, 'USD') * sign
			rescue
				0.00
			end
		end
		def self.search_for(a)
			if a.size == 0
				raise "no search specified"
			elsif a[0] == '*'
				find_all
			elsif a[0] =~ /\(\)/
				find_all("parent is null")
			end
		end
		def self.find_tree(treeq)
			if treeq.empty?
				find_all('parent is null')
			else
				find_all("parent in (" << treeq.split(',').map { |f| "'#{f}'" }.join(',') << ") or parent is null")
			end
		end
	end

	class Bill < Base
		def self.table_name; 'bills'; end
		has_one :vendor
	end

	class AbstractTransaction
		attr_accessor :amount, :fromaccount, :toaccount, :number, :date, :memo
		def validate
			if(amount.nil? or fromaccount.nil?)
				raise ArgumentError.new("account or amount is nil")
			end
			#$stderr.puts(self.inspect << " " << @amount << " #{@amount.to_f}")
			@fromaccount = @fromaccount.to_i
			@toaccount = @toaccount.to_i
			if !(Date === @date)
				@date = if @date then Date.new(*@date.split('/').map{|n| n.to_i}) else Date.today end
			end
			if @amount == 0.0
				raise ArgumentError.new("amount (#{amount}) is zero")
			end
			if @fromaccount == 0
				raise ArgumentError.new("fromaccount is zero")
			end
			if @toaccount == 0
				raise ArgumentError.new("toaccount is zero")
			end
		end
	end

	class Payment < AbstractTransaction
		def validate
			@toaccount = 1296 # Fixme, don't hardcode
			super
		end
		def save
			Transaction.transaction do
				TransactionItem.transaction do
					t = Transaction.new
					t.date = @date
					t.ttype = 'Payment'
					t.status = 'Completed'
					t.number = @number
					t.memo = @memo
					t.save!
					e1 = TransactionItem.new
					e1.amount = @amount * -1
					e1.account_id = @fromaccount
					e1.number = @number
					t.items << e1
					e2 = TransactionItem.new
					e2.amount = @amount
					e2.account_id = @toaccount
					e2.number = @number
					t.items << e2
					t.save!
					e1.create
					e2.create
				end
			end
		end
	end

	class Refund < Payment
		def save
			@amount = @amount * -1
			@toaccount = 1302
			super
		end
	end

	class Expense < AbstractTransaction
		attr_accessor :date, :payee, :memo
		def validate
			super
			@toaccount = @toaccount.to_i
			if @date
				@date = Date.parse(@date)
			else
				@date = Date.today
			end
			@payee = "" if !@payee
			@memo = "" if !@memo
		end
		def save
			begin
				t = Transaction.new
				t.date = @date
				t.ttype = 'Payment'
				t.payee = @payee
				t.memo = @memo
				t.save
				e = TransactionItem.new
				e.amount = @amount * -1
				e.account_id = @fromaccount
				e.number = number
				e.transaction_id = t.id
				e.save
				e = TransactionItem.new
				e.amount = @amount
				e.account_id = @toaccount # Fixme, don't hardcode, use @toaccount
				e.number = @number
				e.transaction_id = t.id
				e.save
			end
		end
	end

	class Note < Base
		def self.table_name; 'notes'; end
		belongs_to :customer
		def to_s
			note
		end
	end

	# Customer represents an entry in a customers table.
	class Customer < Base
		def self.table_name;  'customers'; end
		has_many :transactions, :class_name => "Elf::Transaction"
		has_many :addresses, :class_name => "Elf::Address"
		has_many :services, :class_name => 'Elf::Service'
		has_many :phones, :class_name => 'Elf::Phone'
		has_many :notes, :class_name => 'Elf::Note'
		belongs_to :account


		def account_name
			if !company or company.empty?
				if first or last
					(first || '') + " " + (last || '')
				else
					name
				end
			else
				company
			end
		end

		def address
			addresses.first
		end

		alias_method :ar_addresses, :addresses
		def addresses
			ar_addresses.reject {|e| e.obsolete_by }
		end

		def active_services
			services.select { |e| e.active? }
		end

		def charge_card(amount)
			if !cardnumber or !cardexpire
				raise 'No card on file'
			end

			gateway = ActiveMerchant::Billing::AuthorizeNetGateway.new(
				:login => $config['authnetlogin'],
				:password => $config['authnetkey']
			)
			cc = ActiveMerchant::Billing::CreditCard.new(
				:first_name => first,
				:last_name => last,
				:number => cardnumber,
				:month => cardexpire.month,
				:year => cardexpire.year,
				:type => case cardnumber[0,1]
					when '3': 'americanexpress'
					when '4': 'visa'
					when '5': 'mastercard'
				end
			)
			response = gateway.authorize(amount, cc, {:customer => name})
			if response.success?
				charge = gateway.capture(amount, response.authorization)
				if charge.success?
					payment = Payment.new
					payment.date = Date.today
					payment.amount = amount
					payment.fromaccount = account.id
					payment.number = response.authorization
					payment.memo = 'Credit Card Charge'
					payment.validate
					payment.save
				end

				return charge
			else
				raise response.message
			end
		end
		
		def emailto
			s = super
			if s and !s.empty?
				s
			else
				if /@/.match? s
					s
				else
					"#{name}@independence.net"
				end
			end
		end

		def self.search_for(a)
			if a.size == 0
				raise "no search specified"
			end
			fields = ["name", "first", "last", "company"]
			find_all(a.map do |e|
				e.downcase!
				"(#{fields.map{ |f| "lower(#{f}) like '%#{e}%'" }.join(' OR ')})"
			end.join(' AND '))
		end

		def generate_invoice(close = true, for_range = nil, period = 'Monthly')
			if for_range and !(Range === for_range)
				for_range = for_range..((for_range >> 1) - 1)
			end
			$stderr.puts "Generating invoice for #{name}"
			if services.empty?
				$stderr.puts "\tNo services"
				return nil
			end

			services = self.services.reject { |e| e.period != period }
			if services.empty?
				$stderr.puts "\tNo #{period} services"
				return nil
			end

			if for_range
				services = services.select do |s|
					(!s.starts or s.starts <= for_range.first) and (!s.ends or s.ends >= for_range.last)
				end
			end

			if services.empty?
				$stderr.puts "\tNo services in range"
				return nil
			end
			invoice = Invoice.new("account_id" => account_id, "status" => "Open", "date" => Date.today) #API Kludge; should be able to say self.invoices << Invoice.new(...)
			invoice.startdate = for_range.first
			invoice.enddate = for_range.last
			unless invoice.save
				puts "There was #{invoice.errors.count} error(s)"
				invoice.errors.each_full { |error| $stderr.puts error }
			end

			services.each do |service|
				if service.period == period and (!service.starts or service.starts <= invoice.startdate) and (!service.ends or service.ends >= invoice.enddate)
					invoice.add_from_service(service)
				end
			end
			if close
				invoice.status = "Closed"
				unless invoice.save
					puts "There was #{invoice.errors.count} error(s)"
						invoice.errors.each_full { |error| $stderr.puts error }
				end
			end
			invoice
		end

	end

	class Invoice < Base
		def self.table_name; 'invoices'; end
		class HistoryItem < Base
			def self.table_name; "invoice_history"; end
		end

		has_many :items, :class_name => 'Elf::InvoiceItem'
		has_many :history, :class_name => 'Elf::Invoice::HistoryItem'
		belongs_to :account
		def self.primary_key
			"id"
		end

		def amount
			items.inject(Money.new(0, 'USD')) { |acc,item| acc += item.total }
		end

		def total
			amount
		end

		def add_from_service(service)
			return nil if service.ends and service.ends <= Date.today
			item = InvoiceItem.new("amount" => service.amount, "invoice_id" => self.id, "description" => service.service.capitalize + ' ' + (service.detail || ''), "quantity" => 1) # API Ditto
			item.save
		end

		def detail_link
			"/elf/o/invoice/#{id}/"
		end

		def self.find_all(conditions = nil, orderings = 'date', limit = nil, joins = nil)
			 o = super
			 o.sort! { |a,b| b.date <=> a.date }
			 o
		end

		def invoice_id
			id
		end

		def sent?
			HistoryItem.find_all("invoice_id = '#{id}' and action = 'Sent'").size > 0
		end

		def totalmessage
			if balance > 0
				"You owe:"
			elsif balance == 0
				"No balance due:"
			else
				"Credit balance remaining:"
			end
		end

		def message
			if account.balance > 0
				if account.customer.cardnumber and !account.customer.cardnumber.empty?
					if account.balance <= amount
						"Your credit card will be billed for the new charges above."
					else
						"We seem to have had problems processing your credit card. Please contact us at (970) 626-3600 so we can get it straightened out! Thanks! We will attempt to charge the new charges listed above."
					end
				elsif
					account.customer.banknum and !account.customer.banknum.empty?
					"Your bank account will be drafted for the new charges above."
				else
					"Please make checks payable to the address above."
				end
			else
				"Thanks for being our customer!"
			end
		end

		EMAIL_DEFAULTS = {:with_message => nil}

		def send_by_email (options = {})
			options = EMAIL_DEFAULTS.merge(options)
			begin
				$stderr.puts("Invoice ##{id}, account #{account.customer.name}")
				m = RMail::Message.new
				m.header['To'] = account.customer.emailto
				#m.header['To'] = 'Test Account <test@theinternetco.net>'
				m.header['From'] = 'The Internet Company Billing <billing@theinternetco.net>'
				m.header['Date'] = Time.now.rfc2822
				m.header['Subject'] = "Invoice ##{id} from The Internet Company"
				m.header['Content-Type'] = 'text/html; charset=UTF-8'
				m.header['MIME-Version'] = '1.0'
				template = Markaby::Builder.new({}, self)
				template.output_helpers = false
				template.html do
					head do
						title "Invoice \##{invoice_id}"
						style :type => 'text/css' do 
							File.read('email.css')
						end
					end
					body do
						h1 "Invoice \##{invoice_id}, for account #{account.customer.name}" 
						h2 'From:'
						p do
							text("The Internet Company"); br
							text("133 North Lena Street, #3"); br
							text("P.O. Box 471"); br
							text("Ridgway, CO 81432-0471")
						end
						h2 "To:"
						p do
							customer = account.customer
							if customer.first or customer.last
								text("#{customer.first} #{customer.last}"); br
							end
							if customer.company
								text(customer.company); br
							end
							if customer.address
								if customer.address.freeform
									span :style=>'white-space: pre' do
										customer.address.freeform
									end
								else
									a = customer.address.formatted
									text(a.street); br
									text("#{a.city}, #{a.state}, #{a.zip}"); br
								end
							end
						end

						if startdate and enddate
							p "Invoice period: #{startdate.strftime("%Y/%m/%d")} to #{enddate.strftime("%Y/%m/%d")}"
						else
							p "Invoice date: #{date.strftime("%Y/%m/%d")}"
						end

						table do
							tr do
								th(:colspan => '4') { "Previous Balance" }
								td.numeric { "$#{(account.balance - total)}" }
							end
							tr do
								th :colspan => '4' do 'New Charges' end
							end
							tr do
								th.numeric 'Quantity'
								th :colspan => '2' do 'Description' end
								th.numeric 'Amount'
								th.numeric 'Total'
							end
							items.each do |item|
								tr do
									td.numeric item.quantity
									td :colspan => '2' do item.description end
									td.numeric "$#{item.amount}"
									td.numeric "$#{item.total}"
								end
							end
							tr do
								th :colspan => '4' do
									'Total New'
								end
								td.numeric "$#{total}"
							end
							tr do
								th :colspan => '4' do
									'Your Balance'
								end
								td.numeric do "$#{account.balance}" end
							end
						end

						if message
							p { message }
						end

						if options[:with_message]
							p { options[:with_message] }
						end
								
					end
				end

				m.body = [template.to_s].pack('M')
				m.header['Content-Transfer-Encoding'] = 'quoted-printable'
				begin
					Net::SMTP.start('mail.theinternetco.net', 587, 'theinternetco.net', 'dev.theinternetco.net', 'ooX9ooli', :plain) do |smtp|
						smtp.send_message m.to_s, 'billing@theinternetco.net', RMail::Address.new(m.header['To']).address
						m.header['Subject'] = 'Copy: ' + m.header['Subject']
						smtp.send_message m.to_s, 'billing@theinternetco.net', 'billing@theinternetco.net'
					end
					hi = HistoryItem.new("invoice_id" => self.id, "action" => "Sent", "detail" => "to #{m.header['To']}", "date" => Date.today)
					hi.save
				rescue Net::SMTPServerBusy, TimeoutError => e
					trycount ||= 0
					sleep 5
					trycount += 1
					if trycount < 10
						puts "Retry..."
						retry
					end
				end
			rescue NoMethodError => e
				$stderr.puts "Error #{e} handling invoice ##{id}: #{e.backtrace.join("\n")}"
				return
			end
		end
	end

	class Phone < Base
		def self.table_name; 'phones'; end
		def to_s
			phone
		end
	end

	class InvoiceItem < Base
		def self.table_name; 'invoice_items'; end
		def total
			amount * quantity
		end

		def amount
			val = attributes_before_type_cast['amount']
			Money.new(val * 100, 'USD')
		end
	end

	class TransactionItem < Base
		def self.table_name
			'transaction_items'
		end
		belongs_to :account
		belongs_to :transaction

		def amount
			val = attributes_before_type_cast['amount']
			Money.new(val * 100, 'USD')
		end
		#aggregate :total do |sum,item| sum ||= 0; sum = sum + item.amount end
		#def self.find_all(conditions = nil, orderings = nil, limit = nil, joins = 'INNER JOIN transactions on (transactions.id = transaction_items.transaction_id)')
		#	r = super(conditions, orderings, limit, joins)
		#	r.sort! { |a,b| b.date <=> a.date }
		#	r
		#end
	end

	class Transaction < Base
		def self.table_name; 'transactions'; end
		#belongs_to :account, :class_name => 'Elf::Account'
		has_many :items, :class_name => "Elf::TransactionItem"
		def amount
			items.inject(0) { |acc,e| acc += e.amount }
		end
	end

	class Service < Base
		def self.table_name; 'services'; end
		def active?
			!self.ends or self.ends >= Date.today
		end
		def amount
			val = attributes_before_type_cast['amount']
			Money.new(val * 100, 'USD')
		end
	end

	class Address < Base
		def self.table_name
			"addresses"
		end
		def formatted
			self if !freeform
		end
	end

	class CardBatch < Base
		has_many :items, :class_name => 'Elf::CreditCards::CardBatchItem'
		def self.table_name
			"card_batches"
		end
	end

	class CardBatchItem < Base
		belongs_to :customer
		belongs_to :cardbatch, :class_name => 'Elf::CreditCards::CardBatch', :foreign_key => 'cardbatch_id'
		def self.table_name
			"card_batch_items"
		end

		def amount
			val = attributes_before_type_cast['amount']
			Money.new(val * 100, 'USD')
		end

		def charge!(capture = true)
			self.status = 'Authorizing'
			save!
			gateway = ActiveMerchant::Billing::AuthorizeNetGateway.new(
				:login => $config['authnetlogin'],
				:password => $config['authnetkey']
			)
			cc = ActiveMerchant::Billing::CreditCard.new(
				:first_name => customer.first,
				:last_name => customer.last,
				:number => customer.cardnumber,
				:month => customer.cardexpire.month,
				:year => customer.cardexpire.year,
				:type => case customer.cardnumber[0,1]
					when '3': 'americanexpress'
					when '4': 'visa'
					when '5': 'mastercard'
				end
			)
			if !cc.valid?
				self.status = 'Invalid'
				save!
				return self
			end
			response = gateway.authorize(amount, cc, {:customer => customer.name})
			if response.success?
				self.status = 'Authorized'
				self.authorization = response.authorization
				save!
				if capture
					self.class.transaction do
						response = gateway.capture(amount, response.authorization)
						if response.success?
							self.status = 'Completed'
							save!
						else
							self.status = 'Error'
							self.message = response.message
							save!
						end
					end
				end
			else
				self.status = 'Error'
				self.message = response.message
				save!
			end
			if status == 'Error'
				raise StandardError, response.message 
			end
			return self
		end
	end

	module CreditCards
		CardBatch = Elf::Models::CardBatch
		CardBatchItem = Elf::Models::CardBatchItem
	end

	class Pwent < Base
		def self.table_name
			"passwd"
		end
		def self.primary_key
			"uid"
		end
		has_many :logins, :class_name => 'Elf::Login'
	end

	class Login < Base
		belongs_to :pwent, :class_name => 'Elf::Pwent', :foreign_key => 'uid'
		def self.table_name
			"passwd_names"
		end
	end

		class Vendor < Base
			def self.table_name; 'vendors'; end
			belongs_to :account
			belongs_to :expense_account, :class_name => 'Account', :foreign_key => 'expense_account_id'
		end

	end

	include Models

	module Controllers

		class BillingHistory < R '/customers/(\d+)/billinghistory'
			def get(customer)
				@customer = Elf::Customer.find(customer.to_i)
				render :billinghistory
			end
		end

		class CardBatchList < R '/cardbatches/list'
			def get
				@batches = CardBatch.find(:all)
				render :cardbatchlist
			end
		end

		class CardBatchView < R '/cardbatches/(\d+)'
			def get(id)
				@batch = CardBatch.find(id)
				render :cardbatchview
			end
		end

		class CustomerOverview < R '/customers/(\d+)'
			def get(id)
				@customer = Elf::Customer.find(id.to_i)
				render :customeroverview
			end
		end

		class CustomerEdit < R '/customers/(\d+)/edit'
			def get(id)
				@customer = Elf::Customer.find(id.to_i)
				render :customeredit
			end

			def post(id)
				@customer = Elf::Customer.find(id.to_i)
				@customer.first = @input.first
				@customer.last = @input.last
				@customer.company = @input.company
				@customer.emailto = @input.emailto
				@customer.save!
				redirect R(CustomerOverview, @customer.id)
			end
		end

		class ChargeCard < R '/customers/(\d+)/chargecard'
			def get(id)
				@customer = Elf::Customer.find(id.to_i)
				render :chargecard
			end

			def post(id)
				@customer = Elf::Customer.find(id.to_i)
				response = @customer.charge_card(Money.new(BigDecimal.new(@input.amount) * 100, 'USD'))
				if response.success?
					redirect R(CustomerOverview, @customer.id)
				else
					raise StandardError, response.message 
				end
			end
		end

		class CustomerFinder < R '/customers/find'
			def get
				search = @input.q
				@results = Elf::Models::Customer.find(:all, :conditions => ["name ilike ? or first ilike ? or last ilike ? or company ilike ?", *(["%#{@input.q}%"] * 4)])
				render :customerlist
			end
		end

		class Index < R '/'
			def get
				render :index
			end
		end

		class Invoice < R '/invoice/(\d+)'
			def get(id)
				@invoice = Elf::Invoice.find(id.to_i)
				render :invoice
			end
		end

		class InvoiceSendEmail < R '/invoice/(\d+)/sendemail'
			def post(id)
				@invoice = Elf::Invoice.find(id.to_i)
				@invoice.send_by_email
				redirect R(Invoice, id)
			end
		end

		class NewPayment < R '/payment/new_for_account/(\d+)'
			def get(account)
				@account_id = account.to_i
				render :newpayment
			end

			def post(account)
				@account = Elf::Account.find(account.to_i)
				payment = Payment.new
				payment.date = @input.date
				payment.amount = Money.new(BigDecimal.new(@input.amount), 'USD')
				payment.fromaccount = account.to_i
				payment.number = @input.number
				payment.validate
				payment.save
				redirect R(CustomerOverview, @account.customer.id)
			end
		end

		class Style < R '/(.*\.css)'
			def get(file)
				#@headers['Content-type'] = 'text/css'
				@body = File.read(File.join(File.dirname(__FILE__), file))
			end
		end

		class VendorAddBill < R '/vendors/(\d+)/newbill'
			def get(id)
				@vendor = Vendor.find(id.to_i)
				render :vendoraddbill
			end

			def post(id)
				@vendor = Vendor.find(id.to_i)
				Vendor.transaction do
					b = Bill.new
					b.date = @input.date
					b.vendor_id = @vendor.id
					t = Transaction.new
					t.date = @input.date
					t.ttype = 'Misc'
					t.create
					e1 = TransactionItem.new(:amount => Money.new(BigDecimal.new(@input.amount) * 100, 'USD') * -1, :account_id => @vendor.account.id)
					t.items << e1
					e2 = TransactionItem.new(:amount => Money.new(BigDecimal.new(@input.amount) * 100, 'USD'), :account_id => (@vendor.expense_account ? @vendor.expense_account.id : 1289))
					t.items << e2
					e1.create
					e2.create
					b.transaction_id = t.id
					b.create
					# Enter bill, create transaction
				end
				redirect R(VendorOverview, @vendor.id)
			end
		end

		class VendorFinder < R '/vendors/find'
			def get
				search = @input.q
				@results = Elf::Vendor.find(:all, :conditions => ["name ilike ?", *(["%#{@input.q}%"])])
				render :vendorlist
			end
		end

		class VendorOverview < R '/vendors/(\d+)'
			def get(id)
				@vendor = Vendor.find(id.to_i)
				render :vendoroverview
			end
		end
	end

	module Views
		def billinghistory
			h1 "Billing History for #{@customer.account_name}"
			table do
				tr do
					th.numeric "Id"
					th.numeric "Number"
					th "Memo"
					th.numeric "Amount"
					th "Date"
					th "Status"
				end
				@customer.account.entries.each do |t|
					tr do
						td.numeric t.transaction_id
						td.numeric t.number
						if t.transaction.ttype == 'Invoice' and t.transaction.memo =~ /^Invoice #(\d+)$/
							td { a(t.transaction.memo, :href=> R(Controllers::Invoice, $1)) } # FIXME: Invoice
						else
							td t.transaction.memo
						end
						td.numeric t.amount
						td t.transaction.date.strftime('%Y-%m-%d')
						td t.status
					end
				end
			end
		end

		def chargecard
			h1 "Charge #{@customer.account_name}'s card"
			form :action => R(ChargeCard, @customer.id), :method => 'POST' do
				p do 
					text "Charge " 
					input :type => 'text', :name => 'amount', :value => @input.amount, :size => 6
					text " to card *#{@customer.cardnumber[-4..-1]}?"
				end
				input :type => 'submit', :value => "Charge"
			end
		end

		def cardbatchlist
			h1 'Credit Card Batches'
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
			h1 "Card Batch \##{@batch.id}"
			p do
				success = @batch.items.select { |i| i.status == 'Completed' }
				"#{success.size} completed successfully, total of #{success.inject(Money.new(0, 'USD')) { |a,e| a += e.amount}}"
			end
			failures = @batch.items.reject { |i| i.status == 'Completed' }
			table do
				tr do
					th { 'Account' }
					th { 'First' }
					th { 'Last' }
					th { 'Card' }
					th { 'Failure' }
				end
				failures.each do |item|
					tr do
						td { a(item.name, :href => R(CustomerOverview, item.customer.id)) }
						td { item.first }
						td { item.last }
						td { "*#{item.cardnumber[-4..-1]}, #{item.cardexpire.strftime('%Y/%m')}" }
						td do
							if item.status == 'Error'
								item.message
							else
								"#{item.status}#{if item.cardexpire < Date.parse(batch.date.strftime('%Y/%m/%d')): ': Card Expired' end}"
							end
						end
					end
				end
			end
		end

		def customeroverview
			h1 "Account Overview for #{@customer.account_name}"

			p @customer.emailto

			@customer.addresses.each do |address|
				p.address do
					text("#{address.first} #{address.last}"); br
					if address.company and !address.company.empty?
						text("#{address.company}"); br
					end
					text("#{address.street}"); br
					text("#{address.city} #{address.state} #{address.zip}"); br
				end
			end

			if !@customer.phones.empty?
				h2 "Phone numbers"
				ul.phones do
					@customer.phones.each do |phone|
						li phone
					end
				end
			end

			h2 "Other info"
			p do
				text("Account Balance: $#{@customer.account.balance}")
				if @customer.account.balance > Money.new(0, 'USD') and @customer.cardnumber
					text ' '
					a('Charge Card', :href => R(ChargeCard, @customer.id, {'amount' => @customer.account.balance}))
				end
			end
			if @customer.cardnumber
				p "Bills to #{case @customer.cardnumber[0,1]; when '4': "Visa"; when '5': 'Mastercard'; when '3': "American Express"; else "Card"; end} ending *#{@customer.cardnumber[-4..-1]}, expires #{@customer.cardexpire.strftime('%Y/%m')}"
			end

			h2 "Services"
			table do
				@customer.services.each do |s|
					if !s.ends or s.ends >= Date.today
						tr do
							td((s.service || '') + " for " + (s.detail || ''))
							td "$#{s.amount}"
							td do
								"#{s.period.downcase} each #{if s.period == 'Monthly': "#{s.starts.day} of the month" else s.starts.strftime('%B %e') end}"
							end
							td do
								if s.starts > Date.today: text(" starts #{s.starts}") end
								if s.ends: text(" ends #{s.ends}") end
							end
						end
					end
				end
			end

			p.screen do
				if !@customer.account.invoices.empty?
					a('Billing History', :href=>R(BillingHistory, @customer.id))
				end
				text ' '
				a('Record Payment', :href=> R(NewPayment, @customer.account.id))
				text ' '
				a('Edit Record', :href=> R(CustomerEdit, @customer.id))
			end
				
		end

		def customeredit
			h1 "Edit customer record"
			form :action => R(CustomerEdit, @customer.id), :method => 'post' do
				table do
					tr do
						td { label(:for => 'name') { 'Name ' } }
						td { input :name => 'name', :value => @customer.name } 
					end
					tr do
						td { label(:for => 'first') { 'First' } }
						td { input :name => 'first', :value => @customer.first } 
					end
					tr do
						td { label(:for => 'last') { 'Last' } }
						td { input :name => 'last', :value => @customer.last } 
					end
					tr do
						td { label(:for => 'company') { 'Company' } }
						td { input :name => 'company', :value => @customer.company } 
					end
					tr do
						td { label(:for => 'emailto') { 'Email' } }
						td { input :name => 'emailto', :value => @customer.emailto } 
					end
					tr do
						td { }
						td { input :type => 'submit', :value => 'Save' }
					end
				end
			end
		end

		def customerlist
			h1 "Customers matching \"#{@input.q}\""
			ul do 
				@results.each do |e|
					li do
						a(e.name, :href=> R(CustomerOverview, e.id))
						text(" #{e.first} #{e.last} #{e.company}") 
						a('Record Payment', :href=> R(NewPayment, e.account.id))
					end
				end
			end
		end

		def index
			h1 'Accounting'
			h2 'Customers'
			form :action => R(CustomerFinder), :method => 'GET' do
				input :name => 'q', :type => 'text'
				input :type => 'submit', :value => 'Find'
			end

			h2 'Vendors'
			form :action => R(VendorFinder), :method => 'GET' do
				input :name => 'q', :type => 'text'
				input :type => 'submit', :value => 'Find'
			end

			h2 'Other'
			p do
				a('Credit Card Batches', :href=> R(CardBatchList))
			end

		end

		def invoice
			h1 { text("Invoice \##{@invoice.id}"); span.screen { "(#{@invoice.status})" } }
			table do
				tr do
					th.numeric "Qty."
					th "Description"
					th "Amount"
					th "Total"
				end
				@invoice.items.each do |item|
					tr do
						td.numeric item.quantity
						td item.description
						td.numeric item.amount
						td.numeric item.total
					end
				end
				tr do
					th(:colspan => 3) { "Total" }
					td.numeric @invoice.total
				end
			end

			form.screen :action => R(InvoiceSendEmail, @invoice.id), :method => 'post' do
				input :type => 'submit', :value => 'Send by Email'
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

		def vendoraddbill
			h1 "Add bill from #{@vendor.name}"
			form :action => R(VendorAddBill, @vendor.id), :method => 'post' do
				table do
					tr do
						td { label(:for => 'date') { 'Date' } }
						td { input :type => 'text', :name => 'date', :value => Time.now.strftime('%Y/%m/%d') }
					end
					tr do
						td { label(:for => 'amount') { 'Amount' } }
						td { input :type => 'text', :name => 'amount' }
					end
					tr do
						td { label(:for => 'number') { 'Number' } }
						td { input :type => 'text', :name => 'number' }
					end
					tr do
						td { }
						td { input :type => 'submit', :value => 'Save' }
					end
				end
			end
		end

		def vendorlist
			h1 "Vendors matching \"#{@input.q}\""
			ul do 
				@results.each do |e|
					li do
						a(e.name , :href=> R(VendorOverview, e.id))
					end
				end
			end
		end

		def vendoroverview
			h1 "Vendor -- #{@vendor.name}"
			p "Current Balance: $#{@vendor.account.balance}"
			p.screen do
				a 'History' # FIXME
				text ' '
				a 'Pay' # FIXME
				text ' '
				a 'Add Bill', :href => R(VendorAddBill, @vendor.id)
			end
		end

		def layout
			html do
				head do
					title "Elf"
					link :rel => 'Stylesheet', :href=> '/site.css'
				end
				body do
					yield
				end
			end
		end
	end

end

require 'elf/actions'
