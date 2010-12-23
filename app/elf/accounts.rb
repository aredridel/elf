require 'money'

LEDGER_LINES=66

module Elf::Models

	# An account, in the accounting sense. Balance comes later.
	class Account < Base
		has_one :contact
		has_many :entries, :class_name => 'TxnItem', :order => 'txns.date ASC, txns.id ASC', :include => 'txn'
		has_many :invoices, :order => 'date ASC, id ASC'
		has_many :subaccounts, :class_name => "Account", :foreign_key => 'parent'
		belongs_to :closes, :class_name => 'Account', :foreign_key => 'closes_account_id'
		has_one :closed_by, :class_name => 'Account', :foreign_key => 'closes_account_id'

		def self.find_all(conditions = nil, orderings = 'id', limit = nil, joins = nil)
			super
		end

		def display_name
			base = "#{description} (#{account_type})"
			base << " #{contact.name}" if contact
			base
		end

		def open_invoices
			invoices.select { |i| !i.closed? }
		end

		def balance(date_or_tid = nil)
			date = tid = nil
			#Txn.find_all("account_id = '#{id}'").inject(0) { |acc,t| acc += t.amount.to_f }
			case date_or_tid
			when Time
				date = date_or_tid
				tid = nil
			when String
				date = Time.parse(date_or_tid)
				tid = nil
			when nil
			else
				date = nil
				tid = date_or_tid
			end
			begin
				ret = Money.new(connection.select_one(
					"SELECT SUM(amt) AS balance 
						FROM txn_items 
							INNER JOIN accounts 
								ON (txn_items.account_id = accounts.id)
							#{if date then "INNER JOIN txns 	
								ON (txn_items.txn_id = txns.id 
									AND transactions.date <= '#{date.strftime("%Y-%m-%d")}')" else "" end}
							#{if tid then "INNER JOIN txns
								ON (txn_items.txn_id = txns.id
									AND txns.id <= #{tid})" else "" end}
						WHERE accounts.path like '#{path}.%' OR accounts.id = '#{id}'"
				)['balance'].to_i) * sign
				return ret
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

		def credits
			entries.select { |e| e.amount * sign > 0 }
		end

		def debits
			entries.select { |e| e.amount * sign < 0 }
		end
	end

end

module Elf::Controllers
	class AccountCredit < R '/accounts/(\d+)/credit'
		def get(id)
			@account = Elf::Company.find(1).accounts.find(id.to_i)
			@page_title = "Credit to account #{@account.id}"
			render :accountcredit
		end
		def post(id)
			@account = Elf::Company.find(1).accounts.find(id.to_i)
			amount = Money.new(BigDecimal.new(@input.amount) * 100)
			t = Txn.new
			t.date = @input.date
			t.ttype = 'Credit'
			t.memo = @input.reason
			t.save!
			e1 = TxnItem.new(:amount => amount * -1, :account_id => @account.id)
			t.items << e1
			e2 = TxnItem.new(:amount => amount, :account_id => 1302)
			t.items << e2
			e1.save!
			e2.save!
			redirect R(CustomerOverview, @account.contact.id)
		end
	end

	class AccountGroups < R '/accounts/chart'
		def get
			@accountgroups = Company.find(1).accounts(:all).group_by(&:account_group).keys
			render :accountgroups
		end
	end

	class AccountBalanceSheet < R '/accounts/balances'
		def get
			@a = 'not done yet'
		end
	end

	class Accounts < R '/accounts/chart/([^/]+)/'
		def get(t)
			@account_group = t
			@accounts = Company.find(1).accounts.find(:all, :conditions => ['account_group = ?', t])
			render :accounts
		end
	end

	class AccountFind < R '/accounts/find'
		def get
			Company.find(1).accounts.find
		end
	end

	class AccountShow < R '/accounts/(\d+)'
		def get(id)
			@account = Company.find(1).accounts.find(id)
			render :account
		end
	end

	class AccountHistory < R '/customers/(\d+|[^/]+)/accounthistory', '/customers/(\d+)/invoices/'
		def get(customer)
			@contact = getcontact(customer)
			@page_title = "Billing History for #{@contact.account_name}"
			render :accounthistorydetail
		end
	end


end

module Elf::Views
	def accounts
		#header do
			h1 @account_group + ' Accounts'
		#end
		ul do
			@accounts.each do |a|
				li { a("#{a.id}: #{a.display_name}", :href => R(AccountShow, a.id)) }
			end
		end
	end

	def accountgroups
		#header do
			h1 'Accounts'
		#end
		ul do
			@accountgroups.each do |g|
				g = "Other" if !g
				li { a(g, :href => R(Accounts, g)) }
			end
		end
	end

	def accountcredit
		form :action => R(AccountCredit, @account.id), :method => 'post' do
			p { text("Date: "); input :type => 'text', :name => 'date', :value => Date.today.strftime('%Y/%m/%d') }
			p { text("Amount: "); input :type => 'text', :name => 'amount' }
			p { text("Reason: "); input :type => 'text', :name => 'reason' }
			input :type => 'submit', :value => 'Credit'
		end
	end

	def account
		#header do
			h1 "Account #{@account.id}: #{@account.display_name}"
		#end
		if @account.closes
			p do
				text "Closes account "
				a(@account.closes.id, :href=>R(Account, @acount.closes))
			end
		end
		if @account.closed_by
			p do
				text "Closed by account "
				a(@account.closed_by.id, :href=>R(Account, @acount.closed_by))
			end
		end
		table do
			tr do
				th 'Date'
				th 'Memo'
				th 'Debit'
				th 'Credit'
			end
			@account.entries.find(:all, :limit => LEDGER_LINES, :offset => @input.page ? @input.page.to_i * LEDGER_LINES : 0).each do |e|
				tr do
					td e.txn.date.strftime('%Y/%m/%d')
					td e.txn.memo
					td e.amount
				end
				# FIXME: should put all > 0 in Dr and < 0 in Cr for asset and expense
				# accounts, Vice versa for liability, equity, revenue
				e.txn.items.select { |i| i.account != @account }.each do |i|
					tr do
						td { }
						td { '&nbsp;'*5 + "#{i.account.description} #{if i.account.account_type then "(#{i.account.account_type})" end}" }
						td { }
						td { "#{i.amount}" }
					end
				end
			end
		end
		div.controls do
			if @account.entries.count > LEDGER_LINES
				if (@input.page ? @input.page.to_i * LEDGER_LINES : 0) > LEDGER_LINES
					a('Back', :href => R(AccountShow, @account.id, :page => @input.page.to_i - 1))
				else
					span('Back')
				end
				text ' '
				if (@input.page ? @input.page.to_i * LEDGER_LINES + LEDGER_LINES : LEDGER_LINES) < @account.entries.count
					a('Next', :href => R(AccountShow, @account.id, :page => @input.page.to_i + 1))
				else
					span('Next')
				end
			end
		end
	end

	def accounthistorydetail
		total = Money.new(0)
		pending = Money.new(0)
		table do
			thead do
				tr do
					th.numeric "Id"
					th.numeric "Number"
					th "Memo"
					th.numeric "Amount"
					th "Date"
					th "Balance"
				end
			end

			items = @contact.account.invoices.select { |i| i.status != 'Closed' } + @contact.account.entries
			@input.each_pair do |filter, value|
				items = items.select { |i| i.respond_to? filter and i.send(filter).to_s == value }
			end

			items.sort_by do |e|
				case e 
				when Models::TxnItem
					[e.txn.date, e.txn.id]
				else
					[e.date, 0]
				end
			end.each do |t|
				case t
				when Models::TxnItem
					tr do
						td.numeric t.txn_id
						td.numeric t.number
						if t.txn.invoice
							td do
								a(t.txn.memo, :href=> R(InvoiceEdit, t.txn.invoice.account.contact.id, t.txn.invoice.id)) 
								if(t.txn.invoice.job and
								!t.txn.invoice.job.empty?)
									self << " (#{t.txn.invoice.job})"
								end
							end
						else
							td t.txn.memo
						end
						td.numeric t.amount
						total += t.amount
						td t.txn.date.strftime('%Y-%m-%d')
						td.numeric total
					end
					if inv = t.txn.invoice
						inv.items.each do |it|
							tr do
								td ''
								td ''
								td  it.description
								td.numeric it.amount * it.quantity
							end
						end
					end
				else
					tr.unfinished do
						td.numeric 'None'
						td.numeric ''
						td { a("Invoice \##{t.id}#{if t.job then " (#{t.job})" else '' end}", :href => R(InvoiceEdit, t.account.contact.id, t.id)) }
						pending += t.total
						td.numeric t.total
						td t.date.strftime('%Y-%m-%d')
						td t.status
					end
				end
			end
			tr do
				th(:colspan => 3) { "Total" }
				td.numeric total
			end
			if pending > Money.new(0)
				tr do
					th(:colspan => 3) { "Pending" }
					td.numeric pending
				end
				tr do
					th(:colspan => 3) { "Grand total" }
					td.numeric pending + total
				end
			end
		end
	end


end
