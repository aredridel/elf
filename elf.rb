# * Platypus imagines comments....
# <Platypus> // Fred 0.99b
# <Platypus> // A perpetually nervous man in the corner with an abacus.

# Elf. A gnarled, ancient wizardly sort, sitting in the corner, reading slips
# of paper written in an arcane script. He has no other name than simply "Elf".

$:.unshift(File.join(File.dirname(__FILE__), 'local'))

def tee(*s)
	if(s.size > 1)
		n = s.shift
	else
		n = 'debug'
	end
	$logger.debug { "#{n}: #{s[0].inspect}" }
	s[0]
end

$:.unshift  'activerecord/lib'
require 'mvc/website'
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

module MVC
	module Website
		module URIControllerHooks
			def uri
	#			'/' + self.class.name.downcase + '/' + self.send(self.class.primarykey)
				self.class.table_name << '/' << self.send(self.class.primary_key.intern) << '/'
			end
			module_function :uri

			class << self
				attr_accessor :searchpath
			end

			@searchpath = Set.new
			def self.included(s)
				matches = s.name.match(/(.*)::[^:]+/) 
				@searchpath.add Object.const_get(matches[1]) if matches
			end

		end

		class URIController
			def class_for_name(s)
				MVC::Website::URIControllerHooks.searchpath.each do |mod|
					begin
						return mod.const_get(s.capitalize)
					rescue NameError => e
					end
				end
				nil	
			end

			def instance_for_uri(uri)
				ret = nil
				parts = uri.path.split('/')
				parts.shift
				klass = class_for_name(parts[0])
				parts.shift
				if parts[0]
					ret = klass.find(parts[0])
					parts.shift
					parts.each { |p|
						ret = ret.send(p.intern) if p and !p.empty?
					}
				elsif uri.query and !uri.query.empty?
					qs = URI::HTTP::QueryString.new(uri.query)
					if qs['q']
						ret  = klass.search_for qs['q']
					end
				end
				ret
			end

			def view_for_uri(uri)
				obj = instance_for_uri(uri)
				if Array === obj
					if obj.size > 0
						return Amrita::XMLTemplateFile.new(obj[0].class.basename.gsub(/([a-z])([A-Z])/, '\1_\2').downcase + '-list.html')
					elsif obj.size == 0
						return Amrita::XMLTemplateFile.new('none-found.html')
					end
				end
				$logger.debug { obj.class.basename }
				return Amrita::XMLTemplateFile.new(obj.class.basename.downcase + '.html')
			end
		end
	end
end

module Amrita
	class XMLTemplateFile < Amrita::TemplateFile
		def initialize(file)
			super(file)
			self.xml = true
			self.asxml = true
			self.amrita_id = 'amrita:id'
			self.use_compiler = true
		end
	end
end

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

	
	# An account, in the accounting sense. Balance comes later.
	class Account < ActiveRecord::Base
		include Amrita::ExpandByMember
		has_one :customer, :class_name => "Elf::Customer"
		has_many :entries, :class_name => 'Elf::TransactionItem'
		has_many :invoices, :class_name => "Elf::Invoice"
		has_many :subaccounts, :class_name => "Elf::Account", :foreign_key => 'parent'
		def self.find_all(conditions = nil, orderings = 'id', limit = nil, joins = nil)
			super
		end

		def balance
			#Transaction.find_all("account_id = '#{id}'").inject(0) { |acc,t| acc += t.amount.to_f }
			begin
				connection.select_one(
					"SELECT SUM(amount) AS balance 
						FROM transaction_items 
							INNER JOIN accounts 
								ON (transaction_items.account_id = accounts.id)
						WHERE accounts.path like '#{path}.%' OR accounts.id = '#{id}'"
				)['balance'].to_f * sign
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

	class AbstractTransaction
		attr_accessor :amount, :fromaccount, :toaccount, :number, :date
		def validate
			if(amount.nil? or fromaccount.nil?)
				raise ArgumentError.new("account or amount is nil")
			end
			#$stderr.puts(self.inspect << " " << @amount << " #{@amount.to_f}")
			@amount = @amount.to_f
			@fromaccount = @fromaccount.to_i
			@toaccount = @toaccount.to_i
			@date = if @date then Date.new(*@date.split('/').map{|n| n.to_i}) else Date.today end
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
			begin
				t = Transaction.new
				t.date = @date
				t.ttype = 'Payment'
				t.status = 'Completed'
				t.number = @number
				t.save
				e = TransactionItem.new
				e.amount = -@amount
				e.account_id = @fromaccount
				e.number = @number
				e.transaction_id = t.id
				e.save
				e = TransactionItem.new
				e.amount = @amount
				e.account_id = @toaccount
				e.number = @number
				e.transaction_id = t.id
				e.save
			end
		end
	end

	class Refund < Payment
		def save
			@amount = -@amount
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
				e.amount = -@amount
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

	class Note < ActiveRecord::Base
		include Amrita::ExpandByMember
		belongs_to :customer, :class_name => "Elf::Customer"
		def to_s
			note
		end
	end

	# Customer represents an entry in a customers table.
	class Customer < ActiveRecord::Base
		include Amrita::ExpandByMember
		include MVC::Website::URIControllerHooks
		has_many :transactions, :class_name => "Elf::Transaction"
		has_many :addresses, :class_name => "Elf::Address"
		has_many :services, :class_name => 'Elf::Service'
		has_many :phones, :class_name => 'Elf::Phone'
		has_many :notes, :class_name => 'Elf::Note'
		has_many :subaccounts, :class_name => 'Elf::Customer', :foreign_key => 'billto'
		belongs_to :account, :class_name => 'Elf::Account', :foreign_key => 'account_id'

		def address
			addresses[0]
		end

		alias_method :ar_addresses, :addresses
		def addresses
			ar_addresses.reject {|e| e.obsolete_by }
		end

		def active_services
			services.select { |e| e.active? }
		end
		
		def emailto
			s = super
			if s and !s.empty?
				s
			else
				"#{name}@independence.net"
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
			$stderr.puts "Generating invoice for #{name}"
			if !has_services?
				$stderr.puts "\tNo services"
				return nil
			end
			if services.reject { |e| e.period != period }.empty?
				$stderr.puts "\tNo #{period} services"
				return nil
			end
			if billto and !billto.strip.empty?
				$stderr.puts "\tNot main account"
				return nil
			end
			invoice = Invoice.new("account_id" => account_id, "status" => "Open", "date" => Date.today) #API Kludge; should be able to say self.invoices << Invoice.new(...)
			if Range === for_range
				invoice.startdate = for_range.first
				invoice.enddate = for_range.last
			else
				invoice.startdate = for_range
				invoice.enddate = for_range >> 1
			end
			unless invoice.save
				puts "There was #{invoice.errors.count} error(s)"
				invoice.errors.each_full { |error| $stderr.puts error }
			end

			services.each do |service|
				if service.period == period
					invoice.add_from_service(service)
				end
			end
			subaccounts.each do |subaccount|
				subaccount.services.each do |service|
					if service.period == period
						invoice.add_from_service(service)
					end
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

	class Invoice < ActiveRecord::Base
		class HistoryItem < ActiveRecord::Base
			include Amrita::ExpandByMember
			def self.table_name
				"invoice_history"
			end
		end

		include Amrita::ExpandByMember
		has_many :items, :class_name => 'Elf::InvoiceItem'
		has_many :history, :class_name => 'Elf::Invoice::HistoryItem'
		belongs_to :account, :class_name => 'Elf::Account'
		def self.primary_key
			"id"
		end
		def amount
			items.inject(0) { |acc,item| acc += item.total }
		end
		alias :total :amount

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

		def sent?
			HistoryItem.find_all("invoice_id = '#{id}' and action = 'Sent'").size > 0
		end

		EMAIL_DEFAULTS = {:with_message => ''}

		def send_by_email (options = {})
			options = EMAIL_DEFAULTS.merge(options)
			begin
				$stderr.puts("Invoice ##{id}, account #{account.customer.name}")
				message = RMail::Message.new
				message.header['To'] = account.customer.emailto
				#message.header['To'] = 'Test Account <test@theinternetco.net>'
				message.header['From'] = 'The Internet Company Billing <billing@theinternetco.net>'
				message.header['Date'] = Time.now.rfc2822
				message.header['Subject'] = "Invoice ##{id} from The Internet Company"
				message.header['Content-Type'] = 'text/html; charset=UTF-8'
				message.header['MIME-Version'] = '1.0'
				message.body = ''
				template = Amrita::XMLTemplateFile.new('invoice.email')
				template.expand(message.body, EmailView.new(self, :with_message => options[:with_message]))
				message.body = Base64.encode64(message.body)
				message.header['Content-Transfer-Encoding'] = 'base64'
				begin
					Net::SMTP.start('localhost', 25, 'theinternetco.net', 'dev.theinternetco.net', 'ooX9ooli', :plain) do |smtp|
						smtp.send_message message.to_s, 'billing@theinternetco.net', RMail::Address.new(message.header['To']).address
						message.header['Subject'] = 'Copy: ' + message.header['Subject']
						smtp.send_message message.to_s, 'billing@theinternetco.net', 'billing@theinternetco.net'
						hi = HistoryItem.new("invoice_id" => self.id, "action" => "Sent", "detail" => "to #{message.header['To']}", "date" => Date.today)
						hi.save
					end
				rescue Net::SMTPServerBusy => e
					trycount ||= 0
					sleep 5
					trycount += 1
					retry if trycount < 10
				end
			rescue NoMethodError => e
				$stderr.puts "Error #{e} handling invoice ##{id}: #{e.backtrace.join("\n")}"
				return
			end
		end

		class EmailView < DelegateClass(self)
			attr_accessor :additional_message
			include Amrita::ExpandByMember

			class AccountProxy < DelegateClass(Account)
				include Amrita::ExpandByMember
				def initialize(o, d, i)
					super()
					__setobj__ o
					@date = d
					@invoice = i
				end

				def previousbalance
					balance - @invoice.total
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
			end

			def initialize(obj, i, options = {})
				super()
				__setobj__ obj
				@additional_message = if(options[:with_message]) then options[:with_message] else "" end
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
			def account
				AccountProxy.new(super, date, self)
			end
			def method_missing(sym, *args)
				__getobj__.send(sym, *args)
			end
			def id
				__getobj__.id
			end
		end
	end

	class Phone < ActiveRecord::Base
		include Amrita::ExpandByMember
		def to_s
			phone
		end
	end

	class InvoiceItem < ActiveRecord::Base
		include Amrita::ExpandByMember
		def total
			amount.to_f * quantity.to_f
		end
	end

	class TransactionItem < ActiveRecord::Base
		include Amrita::ExpandByMember
		belongs_to :transaction, :class_name => 'Elf::Transaction'
		belongs_to :account, :class_name => 'Elf::Account'
		#aggregate :total do |sum,item| sum ||= 0; sum = sum + item.amount end
		def self.find_all(conditions = nil, orderings = nil, limit = nil, joins = 'INNER JOIN transactions on (transactions.id = transaction_items.transaction_id)')
			r = super(conditions, orderings, limit, joins)
			r.sort! { |a,b| b.date <=> a.date }
			r
		end
		def list_data
			{ :account => account }
		end

	end

	class Transaction < ActiveRecord::Base
		include Amrita::ExpandByMember
		belongs_to :account, :class_name => 'Elf::Account'
		has_many :items, :class_name => 'Elf::TransactionItem'
		def self.find_all(conditions = nil, orderings = 'date', limit = nil, joins = nil)
			super
		end

		def amount
			items.inject(0) { |acc,e| acc += e.amount.to_f }
		end
	end

	class Service < ActiveRecord::Base
		include Amrita::ExpandByMember
		def active?
			!self.ends or self.ends >= Date.today
		end
	end

	class Address < ActiveRecord::Base
		include Amrita::ExpandByMember
		def self.table_name
			"addresses"
		end
		def formatted
			self if !freeform
		end
	end
	
	module CreditCards

		class CardBatch < ActiveRecord::Base
			has_many :items, :class_name => 'Elf::CreditCards::CardBatchItem'
			def self.table_name
				"card_batches"
			end
		end

		class CardBatchItem < ActiveRecord::Base
			belongs_to :customer, :class_name => 'Elf::Customer'
			belongs_to :cardbatch, :class_name => 'Elf::CreditCards::CardBatch'
		end

	end

end

require 'elf/actions'
