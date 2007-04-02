require 'password'

module Elf
	module Actions
		class Abstract < DatabaseObject
			def run
				raise "Not implemented"
			end
		end

		class CreditCustomer < Abstract
			attr_accessor :amount, :reason, :user
			def namount
				-amount
			end

			def run
				protected do
					@@dbh.exec "INSERT INTO transactions (date, ttype, memo) VALUES (now(), 'Credit', '#{reason}')"
					@@dbh.exec "INSERT INTO transaction_items (account_id, amount, transaction_id) VALUES ((SELECT account_id FROM customers WHERE name = '#{user}'), #{namount}, (SELECT last_value FROM transactions_id_seq))"
					@@dbh.exec "INSERT INTO transaction_items (account_id, amount, transaction_id) VALUES (1302, #{amount}, (SELECT last_value FROM transactions_id_seq))"
				end
			end
		end

		class NewInvoice < Abstract
			def initialize(user)
				@user = user
			end

			def run
				protected do
					@@dbh.exec "INSERT INTO invoices (date, account_id) VALUES (now(), (SELECT account_id FROM customers WHERE name = '#{@user}'))"
					r = @@dbh.query "SELECT last_value FROM invoices_id_seq"
					return r[0]
				end
			end	
		end

		class NewAddress < Abstract
			attr_accessor :customer, :address, :city, :state, :zip, :country
			def initialize(customer)
				@customer = customer
				@address = ''
				@city = ''
				@state = ''
				@zip = ''
				@country = 'US'
			end
			def run
				protected do
					@@dbh.exec "INSERT INTO addresses (customer_id, name, first, last, company, street, city, state, zip, country) VALUES ((SELECT id FROM customers WHERE name = '#{customer}'), '#{customer}', (SELECT first FROM customers WHERE name = '#{customer}'), (SELECT last FROM customers WHERE name = '#{customer}'), (SELECT company FROM customers WHERE name = '#{customer}'), '#{address}', '#{city}', '#{state}' , '#{zip}', '#{country}');"
				end
			end
		end

		class NewCustomer < Abstract
			attr_accessor :user, :first, :last, :company, :email
			def initialize(user)
				@user = user
				@first = ''
				@last = ''
				@company = ''
				@emailto = ''
			end

			def run
				raise "Need first and last names or company" if company.empty? and (first.empty? or last.empty?)
				protected do
					@@dbh.exec "INSERT INTO accounts (description, sign, parent, owner_id) VALUES ('#{user}', 1, 1, 1)"
					@@dbh.exec "INSERT INTO customers (name, first, last, company, account_id, emailto) VALUES ('#{user}', '#{first}', '#{last}', '#{company}', (SELECT last_value FROM accounts_id_seq), '#{email}')"
					r = @@dbh.query "SELECT last_value FROM customers_id_seq"
					return r[0]
				end
			end	
		end
		
		class AddService < Abstract
			def initialize(service)
				@service = service
				@period = 'Monthly'
				@startdate = Time.now
				@send_invoice = false
			end
			attr_accessor :service, :amount, :detail, :customer, :period, :startdate, :send_invoice

			def run
				raise "Must specify amount" unless amount
				raise "Must specify customer" unless customer
				protected do |db|
					db.exec "INSERT INTO services (customer_id, service, detail, amount, starts, period) VALUES ((SELECT id FROM customers WHERE name = '#{customer}'), '#{service}', '#{if !detail then "for #{customer}" else detail end}', #{amount}, '#{startdate.strftime('%Y-%m-%d')}', '#{period}')"
					if send_invoice
						service_id = *db.query("SELECT currval('services_id_seq')")[0]
						customer_id = *db.query("SELECT id FROM customers WHERE name = '#{customer}'")
						cust = Elf::Customer.find(customer_id)
						service = Elf::Service.find(service_id)
						invoice = Elf::Invoice.new("account_id" => cust.account_id, "status" => "Open", "date" => startdate)
						invoice.save
						invoice.add_from_service(service)
						invoice.status = 'Closed'
						invoice.send_by_email
						invoice.save
					end
				end
      end
		end

		class AddItem < Abstract
			def initialize(item)
				@item = item
				@quantity = 1
				@tax = nil
			end

			attr_accessor :quantity, :invoice, :item, :amount, :tax

			def run
				raise "Must specify amount" unless amount
				raise "Must specify invoice" unless invoice
				if tax 
					taxstr = "'#{tax.to_s}'"
				else
					taxstr = nil
				end
				protected do |db|
					db.exec 'INSERT INTO invoice_items (invoice_id, description, amount, quantity, tax_type) VALUES ($1, $2, $3, COALESCE($4, 1.0), $5)', invoice, item, amount, quantity, taxstr
				end
			end
		end

		class FinishInvoice < Abstract
			def initialize(invoice)
				@invoice = invoice
				@send_by_email = false
				@email_message = nil
			end

			attr_accessor :invoice
			attr_accessor :email_message
			attr_accessor :send_by_email

			def run
				Elf::Models::Invoice.transaction do
					i = Elf::Invoice.find(invoice)
					i.close
					opts = {}
					if @email_message
						opts[:message] = @email_message
					end
					i.send_by_email(opts)
				end
			end
		end

		module PasswordSetterHelper
			def pass=(pass)
				@pass = if Password === pass then pass else Password.new(pass) end
			end
		end

		class NewPasswd < Abstract
			attr_accessor :gecos, :homedir, :shell, :gid
			attr_reader :logins, :pass
			def initialize
				self.shell = '/bin/bash'
				self.gid = 1000
				@logins = []
			end
			include PasswordSetterHelper
			def run
				protected do |db|
					if logins.empty?
						raise "No logins specified!" 
					end
					if !homedir or homedir.empty?
						l = logins.select { |e| e.match /@/ }.first
						if l
							user, domain = l.split '@'
							self.homedir = "/home/domains/#{domain}/users/#{user}"
						else
							self.homedir = "/home/users/#{logins.first}"
						end
					end
					db.exec "INSERT INTO passwd (gecos, shell, homedir, gid, passwd) VALUES ('#{gecos}', '#{shell}', '#{homedir}', #{gid}, '#{pass.crypt}')"
					logins.each do |l|
						db.exec "INSERT INTO passwd_names (uid, login) VALUES (currval('passwd_uid_seq'), '#{l}')"
					end
				end
			end
		end

		class ChangePassword < Abstract
			attr_reader :uid
			attr_reader :user
			attr_reader :pass

			include PasswordSetterHelper

			def initialize(user)
				@user = user
			end
			def run
				@login = Elf::Login.find_by_sql("SELECT * FROM passwd_names WHERE login = '#{user}'").first
				if !@login
					raise "Login not found"
				end
				@uid = @login.uid
				@record = @login.pwent
				if !@record
					raise "User not found"
				end
				@record.passwd = pass.crypt
				@record.save
			end
		end

	end

end
