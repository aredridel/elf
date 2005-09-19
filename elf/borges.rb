module Elf
	module Borges
		class DatabaseComponent < ::Borges::Component
			def db
				ActiveRecord::Base.connection.connection
			end
		end
		class DatabaseTask < ::Borges::Task
			def db
				ActiveRecord::Base.connection.connection
			end
		end
		class Payment < DatabaseComponent
			def initialize
				@fromaccount = nil
				@toaccount = nil
				@memo = nil
				@amount = 0.00
			end
			def render_content_on(r)
				r.heading "Enter Payment"
				r.form do
					accounts = Criteria::PostgreSQLTable.new(db, "accounts")
					customers = Criteria::PostgreSQLTable.new(db, "customers")
					account_properties = Criteria::PostgreSQLTable.new(db, 'account_properties')
					l = (accounts.*).inner_join((account_properties.account_id == accounts.id), account_properties).left_outer_join((customers.account_id == accounts.id), customers).select(accounts.id, accounts.description, customers.name)
					#l = Account.find_all(nil, 'id', nil, 'INNER JOIN account_properties ON (account_id = id)')
					r.select(l.map {|e| "#{e[0]} - #{e[1]} - #{e[2]}" }, @account, nil) do |account|
						@account = account
					end
					r.submit_button 'Save' do true end
					r.paragraph @account if @account
				end
			end
			register_application('payment')
		end
		class Reloader < ::Borges::Component
			def render_content_on(r)
				r.form do
					r.submit_button 'Reload' do load 'elf.rb' end
				end
			end
			register_application('reloader')
		end
		class Elf < DatabaseComponent
			def initialize
				@main = MainPage.new(self)
			end
			def render_content_on(r)
				@main.render_on(r)
			end
			def search(name)
				home
				@main.call CustomerSearchTask.new(name)
			end
			def home
				@main.clear_delegate
			end
			def transfer
				home 
				@main.call TransferTask.new
			end

			register_application('elf')

			class MainPage < DatabaseComponent
				attr_accessor :customer_name
				def initialize(frame)
					@frame = frame
				end
				def render_content_on(r)
					r.form do
						r.text_input_on :customer_name, self
						r.submit_button "Find" do 
							STDERR.puts "Search"
							@frame.search(@customer_name)
						end
					end
					r.anchor "Transfer" do
						@frame.transfer
					end
				end
			end

			class CustomerView < DatabaseComponent
				def initialize(customer)
					@customer = customer
				end
				attr_accessor :customer
				def render_content_on(r)
					r.title @customer[0]
					r.paragraph @customer.inspect
					r.paragraph do
						r.anchor "Account" do
							call TransactionList.new(@customer[19])
						end
					end
				end
			end

			class TransactionList < DatabaseComponent
				def initialize(account_id)
					$stderr.puts("Account id #{account_id}")
					@account_id = account_id
					@transactions = db.exec %!
						SELECT transactions.date, transactions.id, transactions.memo, sum(transaction_items.amount) 
							FROM transactions 
								INNER JOIN transaction_items ON (transactions.id = transaction_items.transaction_id) 
							WHERE transaction_items.account_id = '#{@account_id}'
							GROUP BY transactions.date, transactions.id, transactions.memo 
							ORDER BY transactions.date!
				end
				def render_content_on(r)
					r.table do
						r.table_headings "Date", "#", "Description", "Amount"
						@transactions.each do |row|
							r.table_row do
								row.each do |e|
									r.tag_do "td", e
								end
							end
						end
					end
				end
			end

			class TransferTask < DatabaseTask
				def initialize
					@transactionlist = []
					@done = false
				end
				def go
					while !@done
						@transactionlist << (call TransactionBuilder.new)
						$stderr.puts @transactionlist.inspect
					end
				end
				def done
					@done = true
				end
			end

			class AccountSelector < DatabaseComponent
				def initialize
					@accounts = {}
					db.exec("SELECT accounts.id, customers.name FROM accounts LEFT OUTER JOIN customers ON (customers.account_id = accounts.id)").map { |row| ["#{row[1]} (#{row[0]})", row]}.each do |r|
						@accounts[r[0]] = r[1]
					end
				end
				def render_content_on(r)
					r.select @accounts.keys.select { |e| !e.nil? }.sort!, nil do |account|
						@account = @accounts[account]
					end
				end
				attr_accessor :account
			end

			class AmountEntry < DatabaseComponent
				def render_content_on(r)
					r.text_input_on :amount, self
				end
				attr_accessor :amount
			end

			class TransactionEntry < DatabaseComponent
				def initialize
					@ae = AccountSelector.new
					@ame = AmountEntry.new
				end
				def render_content_on(r)
					@ae.render_content_on(r)
					@ame.render_content_on(r)
				end
				def amount
					@ame.amount
				end
				def account
					@ae.account
				end
			end

			class TransactionBuilder < DatabaseComponent
				attr_accessor :date
				attr_accessor :items
				def initialize
					@date = DateTime.now
					@items = []
					@active = TransactionEntry.new
				end
				def render_content_on(r)
					r.form do
						r.table do
							@items.each do |i|
								r.table_row do
									i.each do |e|
										r.tag_do "td", e
									end
								end
							end
						end

						@active.render_content_on(r)
						r.submit_button_on :next, self
					end
				end
				def next
					@items << [@active.account, @active.amount]
					@active = TransactionEntry.new
				end
			end

			class CustomerSearchTask < DatabaseTask
				def initialize(q)
					STDERR.puts "Initializing search #{q}"
					@query = q
				end
				def go
					STDERR.puts "Searching for #{@query}"
					result = db.exec "SELECT * FROM customers WHERE name = '#{@query}'" # Fixme: Escaping

					if result.num_tuples == 0
						no_results
					elsif result.num_tuples == 1
						one_result result[0]
					else
						many_results result
					end
					
				end

				def no_results
					inform("Not found")
				end

				def one_result(result)
					call CustomerView.new(result)
				end

				def many_results(resultlist)
					call CustomerList.new(resultlist.map { |e| e[0] })
				end
			end

		end
	end

end
