require 'ostruct'
require 'active_record'
require 'money'

module Elf
	module Models

		Base = ActiveRecord::Base

		OurAddress = OpenStruct.new(:first => nil, :last => nil, :company => "The Internet Company", :street => 'P.O. Box 471', :city => 'Ridgway', :state => 'CO', :zip => '81432-0471')

	# An account, in the accounting sense. Balance comes later.
	class Account < Base
		has_one :customer
		has_many :entries, :class_name => 'Elf::TransactionItem', :order => 'financial_transactions.date DESC', :include => 'financial_transaction'
		has_many :invoices, :class_name => "Elf::Invoice", :order => 'date DESC, id DESC'
		has_many :subaccounts, :class_name => "Elf::Account", :foreign_key => 'parent'
		def self.find_all(conditions = nil, orderings = 'id', limit = nil, joins = nil)
			super
		end

		def open_invoices
			invoices.select { |i| !i.closed? }
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
				)['balance'].to_i) * sign
			rescue
				Money.new(0)
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
		has_one :vendor
	end

	class Domain < Base
		self.inheritance_column = 'none'
		has_many :records, :order => "length(regexp_replace(name, '[^.]', '', 'g')), name, CASE WHEN type = 'SOA' THEN 0 WHEN type = 'NS' THEN 1 WHEN type = 'MX' THEN 2 WHEN type = 'A' THEN 3 ELSE 4 END, prio, content"
	end

	class Employee < Base
		has_many :paychecks
	end

	class Paycheck < Base
		belongs_to :employee
		belongs_to :check, :class_name => 'Elf::TransactionItem', :foreign_key => 'paycheck_transaction_item_id'
		belongs_to :taxes, :class_name => 'Elf::Transaction', :foreign_key => 'taxes_transaction_id'
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
			if !(Date === @date or Time === @date)
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
			validate
			FinancialTransaction.transaction do
				TransactionItem.transaction do
					t = FinancialTransaction.new
					t.date = @date
					t.ttype = 'Payment'
					t.status = 'Completed'
					t.number = @number
					t.memo = @memo
					e1 = t.transaction_items.build
					e1.amount = @amount * -1
					e1.account = Account.find(@fromaccount)
					e1.number = @number
					e2 = t.transaction_items.build
					e2.amount = @amount
					e2.account = Account.find(@toaccount)
					e2.number = @number
					t.save!
					#e1.save!
					#e2.save!
					return t
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
				t = FinancialTransaction.new
				t.date = @date
				t.ttype = 'Payment'
				t.payee = @payee
				t.memo = @memo
				t.save
				e = TransactionItem.new
				e.amount = @amount * -1
				e.account_id = @fromaccount
				e.number = number
				e.financial_transaction = t
				e.save
				e = TransactionItem.new
				e.amount = @amount
				e.account_id = @toaccount # Fixme, don't hardcode, use @toaccount
				e.number = @number
				e.financial_transaction = t
				e.save
			end
		end
	end

	class Note < Base
		belongs_to :customer
		def to_s
			note
		end
	end

	class Call < Base
	end

	# Customer represents an entry in a customers table.
	class Customer < Base
		has_many :financial_transactions
		has_many :services, :order => 'service, detail, CASE WHEN dependent_on IS NULL THEN 0 ELSE 1 END, service'
		has_many :phones
		has_many :notes
		has_many :purchase_order_items
		belongs_to :account

		def has_address?
			street and city and state and postal and country
		end

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

		def record_payment(amount, date, number = nil)
			payment = Payment.new
			payment.date = date
			payment.amount = amount
			payment.fromaccount = account.id
			payment.number = number
			payment.validate
			payment.save
		end

		def address
			self
		end

		def active_services
			services.select { |e| e.active? }
		end

		def charge_card(amount, cardnumber = nil, cardexpire = nil) # FIXME: Accept a CardBatchItem here
			if !cardnumber 
				cardnumber = self.cardnumber
			end

			if !cardexpire
				cardexpire = self.cardexpire
			end

			if !cardexpire or !cardnumber
				raise "No card on file or entered"
			end

			gateway = ActiveMerchant::Billing::Base.gateway('authorize_net').new(
				:login => $config['authnetlogin'],
				:password => $config['authnetkey']
			)
			ActiveMerchant::Billing::CreditCard.require_verification_value = false
			cc = ActiveMerchant::Billing::CreditCard.new(
				:first_name => first,
				:last_name => last,
				:number => cardnumber,
				:month => cardexpire.month,
				:year => cardexpire.year
			)
			raise "Card not valid: #{cc.errors.inspect}" if !cc.valid?
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
				if s and s =~ /@/
					s
				else
					'paperbill@theinternetco.net'
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
			unless invoice.create
				puts "There was #{invoice.errors.count} error(s)"
				invoice.errors.each_full { |error| $stderr.puts error }
			end

			services.each do |service|
				if service.period == period and (!service.starts or service.starts <= invoice.startdate) and (!service.ends or service.ends >= invoice.enddate)
					invoice.add_from_service(service)
				end
			end
			if close
				invoice.close
				unless invoice.save
					puts "There was #{invoice.errors.count} error(s)"
						invoice.errors.each_full { |error| $stderr.puts error }
				end
			end
			invoice
		end

	end

		class Group < Base #group
			SCHEMA = proc {
				create_table(self.table_name, :force => true, :primary_key => :gid) do |t|
					t.column :name, :string, :limit => 128, :null => false
					t.column :passwd, :string, :limit => 30, :default => 'x'
				end
			}
			# gid, name, passwd
			set_primary_key 'gid'
			has_many :users, :foreign_key => 'gid'
			has_many :group_memberships, :foreign_key => 'gid'
			has_many :members, :through => :group_memberships, :source => :user
		end

		class GroupMembership < Base #group_membership
			SCHEMA = proc {
				create_table self.table_name, :force => true do |t|
					t.column :uid, :integer
					t.column :gid, :integer
				end
				add_index(self.table_name, [:uid, :gid], :unique => true)
			}
			# uid, gid, id
			set_table_name 'group_membership'
			belongs_to :user, :foreign_key => 'uid'#, :order => 'uid'
			belongs_to :group, :foreign_key => 'gid'#, :order => 'gid'
		end

	class Invoice < Base
		class HistoryItem < Base
		end

		has_many :invoice_items, :order => 'invoice_items.id'
		alias items invoice_items
		has_many :history_items
		alias history history_items
		belongs_to :financial_transaction
		belongs_to :account

		def amount
			items.inject(Money.new(0)) { |acc,item| acc = item.total + acc }
		end

		def initialize(params = nil)
			super
			self.date ||= Date.today
		end

		def total
			amount
		end

		def add_from_service(service)
			return nil if service.ends and service.ends <= Date.today
			item = InvoiceItem.new("amount" => service.amount, "description" => [service.service.capitalize, service.detail].compact.join(' for '), "quantity" => 1) # API Ditto
			self.items << item
			item
		end

		def closed?
			status == "Closed"
		end

		def close
			if closed?
				raise "Invoice is already closed"
			end
			FinancialTransaction.transaction do
				create_financial_transaction(:date => Time.now, :ttype => 'Invoice', :memo => "Invoice \##{id}")
				financial_transaction.items.create(:amount => amount, :account => account)
				financial_transaction.items.create(:amount => amount * -1, :account => Account.find(1302))
				save!
				self.status = 'Closed'
				save!
			end
		end

		def detail_link
			"/elf/o/invoice/#{id}/"
		end

		def invoice_id
			id
		end

		def sent?
			HistoryItem.find(:all, :conditions => ["invoice_id = ? and action = 'Sent'", id]).size > 0
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
			if account.balance > Money.new(0)
				if account.customer.cardnumber and !account.customer.cardnumber.empty?
					if account.balance <= amount
						"Your credit card will be billed for the new charges above."
					else
						"We seem to have had problems processing your credit card. Please contact us at (970) 626-3600 so we can get it straightened out! Thanks! We will attempt to charge the new charges listed above."
					end
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
				$stderr.puts("Invoice ##{id}, account #{account.customer.name if account.customer}") 
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
							if customer.has_address?
								if customer.freeformaddress
									span :style=>'white-space: pre' do
										customer.freeformaddress
									end
								else
									text(customer.street); br
									text("#{customer.city}, #{customer.state}, #{customer.postal}"); br
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
						#m.header['Subject'] = 'Copy: ' + m.header['Subject']
						#smtp.send_message m.to_s, 'billing@theinternetco.net', 'billing@theinternetco.net'
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
		def to_s
			phone
		end
	end

	class PurchaseOrder < Base
		has_many :purchase_order_items
		alias items purchase_order_items
	end

	class PurchaseOrderItem < Base
		belongs_to :customer
		belongs_to :purchase_order
		def received?
			received
		end
	end

	class InvoiceItem < Base
		belongs_to :invoice

		def initialize(params = nil)
			super
			self.amount = Money.new(0, 'USD') unless self['amount']
		end

		def total
			amount * quantity
		end

		composed_of :amount, :class_name => 'Money', :mapping => %w(amount cents)
	end

		class Login < Base
			SCHEMA = proc {
				create_table self.table_name, :force => true do |t|
					t.column :uid, :integer
					t.column :login, :string, :limit => 128
				end
				add_index(self.table_name, :login, :unique => true)
			}
			# login, uid, id
			set_table_name 'passwd_names'
			belongs_to :user, :foreign_key => 'uid'
		end

	class TransactionItem < Base
		belongs_to :account
		belongs_to :financial_transaction

		composed_of :amount, :class_name => 'Money', :mapping => %w(amount cents)

		#aggregate :total do |sum,item| sum ||= 0; sum = sum + item.amount end
		#def self.find_all(conditions = nil, orderings = nil, limit = nil, joins = 'INNER JOIN transactions on (transactions.id = transaction_items.transaction_id)')
		#	r = super(conditions, orderings, limit, joins)
		#	r.sort! { |a,b| b.date <=> a.date }
		#	r
		#end
	end

	class FinancialTransaction < Base
		#belongs_to :account, :class_name => 'Elf::Account'
		has_many :transaction_items
		alias items transaction_items
		has_one :invoice
		def amount
			items.inject(Money.new(0)) { |acc,e| acc += e.amount }
		end
	end

	class Service < Base
		belongs_to :customer
		has_many :dependent_services, :foreign_key => 'dependent_on', :class_name => self.name, :order => 'service, detail'
		composed_of :amount, :class_name => 'Money', :mapping => %w(amount cents)
		def active?
			!self.ends or self.ends >= Date.today
		end

		def end_on(date)
			if ends and ends <= Date.today
				raise "Service already ended"
			end
			self.ends = date 
			dependent_services.each do |s|
				s.end_on(date) if !s.ends
			end
			update
		end
	end

	class CardBatch < Base
		has_many :card_batch_items
		alias items card_batch_items
		def self.table_name
			"card_batches"
		end

		def send!
			raise 'Batch already sent' if status != 'In Progress'
			items.each do |i|
				begin
					i.charge! if i.status == nil
				rescue
					$stderr.puts "#{$!} at #{$!.backtrace.first}"
				end
			end
			self.status = 'Sent'
			save!
		end
	end

	class CardBatchItem < Base
		belongs_to :customer
		belongs_to :card_batch
		alias cardbatch card_batch
		belongs_to :invoice
		belongs_to :financial_transaction

		def self.from_invoice(i, wholeinvoice = true)
			if wholeinvoice
				item = new(:amount => i.total, :invoice => i)
			else 
				amount = i.total + i.account.balance
				if amount < Money.new(0)
					amount = Money.new(0)
				elsif amount > i.total
					amount = i.total
				end
				item = new( :amount => amount, :invoice => i)
			end
			if i.account.customer
				item.customer = i.account.customer
				[:first, :last, :name, :street, :city, :state].each do |s|
					item.send("#{s}=", i.account.customer.send(s))
				end
				item.zip = i.account.customer.postal
				item.email = i.account.customer.emailto
				item.cardnumber = i.account.customer.cardnumber
				item.cardexpire = i.account.customer.cardexpire
			end
			item.transaction_type = 'AUTH_CAPTURE'
			item.payment_type = 'CC'
			item
		end

		composed_of :amount, :class_name => 'Money', :mapping => %w(amount cents)

		def charge!(capture = true)
			raise "Already processed" if self.status
			self.status = 'Authorizing'
			save!
			gateway = ActiveMerchant::Billing::AuthorizeNetGateway.new(
				:login => $config['authnetlogin'],
				:password => $config['authnetkey']
			)
			ActiveMerchant::Billing::CreditCard.require_verification_value = false
			cc = ActiveMerchant::Billing::CreditCard.new(
				:first_name => customer.first,
				:last_name => customer.last,
				:number => customer.cardnumber,
				:month => customer.cardexpire.month,
				:year => customer.cardexpire.year
			)
			if !cc.valid?
				self.status = 'Invalid'
				self.message = cc.errors.inspect
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
							pmt = Payment.new
							pmt.fromaccount = customer.account.id
							pmt.date = Time.now
							pmt.memo = 'Credit card charge'
							pmt.amount = self.amount
							pmt.number = self.authorization
							self.financial_transaction = pmt.save
							self.save!
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


	class User < Base
		set_table_name 'passwd'
		set_primary_key 'uid'
		belongs_to :group, :foreign_key => 'gid'
		has_many :group_memberships, :foreign_key => 'uid'
		has_many :groups, :through => :group_memberships, :source => :group
		has_many :logins, :foreign_key => 'uid'
	end

	class Record < Base
		self.inheritance_column = 'records'
		belongs_to :domain
		def sortkey
			self.name.split('.').reverse
		end
	end

	class Vendor < Base
		belongs_to :account
		belongs_to :expense_account, :class_name => 'Account', :foreign_key => 'expense_account_id'
	end

		module CreditCards
			CardBatch = Elf::Models::CardBatch
			CardBatchItem = Elf::Models::CardBatchItem
		end
	end
end

