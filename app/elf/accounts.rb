require 'money'

LEDGER_LINES=66

module Elf::Helpers
	class Context
		attr_reader :starts, :ends, :period
		def initialize(input)
			case input._period
			when /^([1234])Q(\d+)([+]?)$/
				q = $1
				y = $2
				@starts = Date.parse("#{y}-#{Integer(q) * 3 - 2}-1")
				@ends = (@starts >> 3) - 1
				@period = "#{y}Q#{q}#{$3}"
				@ends += 7 if($3 == '+')
			when /^(\d+)Q([1234])([+]?)$/
				q = $2
				y = $1
				@starts = Date.parse("#{y}-#{Integer(q) * 3 - 2}-1")
				@ends = (@starts >> 3) - 1
				@period = "#{y}Q#{q}#{$3}"
				@ends += 7 if($3 == '+') 
			when /^(\d+)-(\d{1,2})([+]?)$/
				@starts = Date.parse("#{$1}-#{$2}-1")
				@ends = (@starts >> 1) - 1
				@period = "#{$1}-#{$2}#{$3}"
				@ends += 7 if($3 == '+') 
			when /^(\d+)([+]?)$/
				@starts = Date.parse("#{$1}-1-1")
				@ends = (@starts >> 12) - 1
				@period = $1+$2
				@ends += 7 if($2 == '+') 
			when /^(\d+)-(\d{1,2})-(\d{1,2})([+]?)$/
				@starts = Date.parse("#{$1}-#{$2}-#{$3}")
				@ends = @starts
				@period = "#{$1}-#{$2}-#{$3}#{$4}"
				@ends += 1 if($4 == '+') 
			when /^ALL$/
				@starts = @ends = nil
				@period = 'ALL'
			when nil
				@starts = Date.parse("#{Date.today.year}-01-01")
				@ends = @starts >> 12
				@period = Date.today.year
			else
				raise ArgumentError, "Bad period"
			end
		end
	end

	def context
		Context.new(@input)
	end
end

module Elf::Models

	# An account, in the accounting sense. Balance comes later.
	class Account < Base
		has_one :contact
		has_one :vendor
		has_many :entries, :class_name => 'TxnItem', :order => 'coalesce(txn_items.date, txns.date) ASC, txns.id ASC', :include => 'txn'
		has_many :invoices, :order => 'date ASC, id ASC'
		has_many :subaccounts, :class_name => "Account", :foreign_key => 'parent'
		belongs_to :closes, :class_name => 'Account', :foreign_key => 'closes_account_id'
		has_one :closed_by, :class_name => 'Account', :foreign_key => 'closes_account_id'
		has_many :txns, :through => :entries

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

		def balance(date_or_txn = nil)
			date = txn = nil
			#Txn.find_all("account_id = '#{id}'").inject(0) { |acc,t| acc += t.amount.to_f }
			case date_or_txn
			when Time
				date = date_or_txn
				txn = nil
			when String
				date = Time.parse(date_or_txn)
				txn = nil
			when Txn
				txn = date_or_txn
				date = txn.date
			when TxnItem
				txn = date_or_txn.txn
				date = date_or_txn.date || txn.date
			when nil
				txn = nil
				date = nil
			else
				txn = entries.find(date_or_txn).txn
				date = txn.date
			end
			begin
				ret = Money.new(connection.select_one(
					"SELECT SUM(amt) AS balance 
						FROM txn_items 
							INNER JOIN accounts 
								ON (txn_items.account_id = accounts.id)
							#{if txn or date then "INNER JOIN txns
								ON (txn_items.txn_id = txns.id
								#{if txn then 
									" AND (coalesce(txn_items.date, txns.date) < '#{date.strftime('%Y-%m-%d')}' 
									    OR (txns.id <= #{txn.id} 
									       AND coalesce(txn_items.date, txns.date) = '#{date.strftime('%Y-%m-%d')}'))"
								else
									""
								end}
								#{if date then
									" AND coalesce(txn_items.date, txns.date) <= '#{date.strftime("%Y-%m-%d")}'"
								else
									""
								end}
								)"
							else
								"" 
							end}
						WHERE accounts.id = '#{id}'"
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
			entries.select { |e| e.amount > 0 }
		end

		def debits
			entries.select { |e| e.amount < 0 }
		end

		def nulls
			entries.select { |e| e.amount == 0 }
		end

		def debit(amount, options = {})
			if !amount.kind_of? Money
				p "Making money out of numbers... in account#debit"
				amount = Money.new(BigDecimal.new(amount.to_s) * 100)
				p amount
			end
			txn = Txn.new({:date => Time.now}.merge(options))
			txn.items << entries.build(:amount => amount, :status => 'Complete')
			return txn
		end

		def credit(amount, options = {})
			if !amount.kind_of? Money
				p "Making money out of numbers... in account#credit"
				amount = Money.new(BigDecimal.new(amount.to_s) * 100)
			end
			txn = Txn.new({:date => Time.now}.merge(options))
			txn.items << entries.build(:amount => amount * -1, :status => 'Complete')
			return txn
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
			@accountgroups = Company.find(1).accounts(:all).group_by(&:account_group).keys.sort_by { |e| e || '' }
			render :accountgroups
		end
	end

	class AccountBalanceSheet < R '/accounts/balances'
		def get
			@a = 'not done yet'
		end
	end

	class Accounts < R '/accounts/chart/([^/]+)/'
		def get(t = nil)
			@account_group = t
			@accounts = Company.find(1).accounts.where(['account_group = ?', t])
			if(context.starts and context.ends)
				@accounts = @accounts.where(['closetime is null or closetime >= ?', context.starts]).where(['opentime is null or opentime <= ?', context.ends])
			end
			render :accounts
		end
	end

	class AccountsAll < R '/accounts/all'
		def get
			@accounts = Company.find(1).accounts.order('description')
			if(accepts.first.first == 'application/json')
				@headers['Content-Type'] = 'application/json'
				return @accounts.group_by { |e| e.account_group }.to_json
			else
				@account_group = 'All'
				render :accounts
			end
		end
	end

	class AccountFind < R '/accounts/find'
		def get
			inc = {}
			if(@input.type)
				inc[@input.type] = [:contact]
			else
				inc = :contact
			end
			@accounts = Company.find(1).accounts
			if(@input.type)
				typetable = Account.reflections[@input.type.intern].table_name
				@accounts = Company.find(1).accounts.includes(inc).where([typetable+'.id IS NOT NULL AND (contacts.name ilike ? OR contacts.first ilike ? OR contacts.last ilike ? OR contacts.company ilike ? OR contacts.emailto ilike ? OR contacts.id IN (SELECT contact_id FROM phones WHERE phone like ?) OR '+typetable+'.name ilike ?)', *(["%#{@input._q}%"] * 7)]).order(['contacts.first', 'contacts.last'])
			else
				@accounts = Company.find(1).accounts.includes(inc).where(["description ilike ?", "%#{@input._q}%"]).order(['contacts.first', 'contacts.last'])
			end
			render :accountlist_with_contacts

		end
	end

	class AccountShow < R '/accounts/(\d+)'
		def get(id)
			@account = Company.find(1).accounts.find(id)
			@counts = Elf::Models::Base.connection.select_all("SELECT
				COUNT(CASE txn_items.status WHEN 'Reconciled' THEN null ELSE false END) AS not_rec, 
				COUNT(CASE txn_items.status WHEN 'Reconciled' THEN true ELSE null END) AS rec, 
				EXTRACT(year FROM coalesce(txn_items.date, txns.date)) || '-' || LPAD(EXTRACT(month FROM COALESCE(txn_items.date, txns.date))::text, 2, '0') AS ymo 
				FROM txn_items 
				INNER JOIN txns ON (txns.id = txn_items.txn_id)
				WHERE account_id = #{id} 
				GROUP BY ymo
				ORDER BY ymo")
			render :account
		end
	end

	class AccountHistory < R '/customers/(\d+|[^/]+)/accounts/(\d+)/history', '/customers/(\d+)/invoices/'
		def get(customer, account)
			@contact = getcontact(customer)
			@account = @contact.accounts.find(account)
			@page_title = "Billing History for #{@contact.account_name}"
			render :accounthistorydetail
		end
	end

	class Txns < R '/txns'
		def post
			@status = 500
			data = JSON.parse(@env['rack.input'].read)
			Txn.transaction do
				@txn = Txn.new
				data.each_pair do |k,v|
					next if k == 'id'
					if k == 'items' and v.is_a? Array
						v.each do |item|
							it = @txn.items.build
							@txn.items.push it
							item.each_pair do |ik,iv|
								next if ik == 'id'
								next if iv.empty?
								if(iv.strip.empty?)
									iv = nil
								else
									iv = iv.strip
								end
								it.send(ik+'=', iv)
							end
						end
					else
						@txn.send(k+'=', v.strip)
					end
				end
				@txn.save!
				@txn.items.each { |e| e.save! }
				@status = 200
				@account = @txn.items.first.account
				render :_txn, @txn.items.first
			end
		end
	end

	class Transaction < R '/accounts/(\d+)/transaction/(\d+)'
		def get(account, txn_item)
			@headers['Content-Type'] = 'text/plain'
			Company.find(1).accounts.find(account).entries.find(txn_item).txn.to_json(:include => [:items])
		end

		def put(account, txn_item)
			@status = 500
			@account = Company.find(1).accounts.find(account)
			data = JSON.parse(@env['rack.input'].read)
			Txn.transaction do
				@txn = @account.entries.find(txn_item).txn
				data.each_pair do |k,v|
					next if k == 'id'
					if k == 'items' and v.is_a? Array
						v.each do |item|
							it = if item['id']
								@txn.items.find(item['id'])
							else
								t = @txn.build_item
								@txn.items << t
								t
							end
							item.each_pair do |ik,iv|
								next if ik == 'id'
								next if iv.empty?
								if iv.strip.empty?
									iv = nil
								else
									iv = iv.strip
								end
								it.send(ik+'=', iv)
							end
							it.save!
						end
					else
						@txn.send(k+'=', v.strip)
					end
				end
				@txn.save!
				@status = 200
				render :_txn, @txn.items.sort_by { |e| e.account == @account ? 0 : 1 }.first
			end
			
		end

	end


end

module Elf::Views
	def accounts
		#header do
			h1 @account_group + ' Accounts'
		#end
		ul do
			@accounts.sort_by {|a| a.display_name }.each do |a|
				li { a("#{a.id}: #{a.display_name}", :href => R(AccountShow, a.id)); text(a.balance) }
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
			p { text("Date: "); input :type => 'text', :name => 'date', :value => Date.today.strftime('%Y-%m-%d') }
			p { text("Amount: "); input :type => 'text', :name => 'amount' }
			p { text("Reason: "); input :type => 'text', :name => 'reason' }
			input :type => 'submit', :value => 'Credit'
		end
	end

	def account
		#header do
			h1 "Account #{@account.id}: #{@account.display_name}"
		#end
		script type: 'text/javascript+protovis' do %Q{
			var groups = ['rec', 'not_rec']
			
			var data = #{@counts.to_json}
			var max = data.reduce(function(p, c) { 
				return Math.max(Math.max(p, c.rec), c.not_rec)
			}, 0)
			console.log(max);
			var y = pv.Scale.linear(0, max).range(0, 150)
			var x = pv.Scale.ordinal(data.map(function(e) { return e.ymo }))
				.splitBanded(0, 500, 4/5)

			var vis = new pv.Panel()
				.width(500)
				.height(150)

			vis.add(pv.Layout.Stack)
				.layers(groups)
				.values(data)
				.x(function(d) { return x(d.ymo) })
				.y(function(d, p) { return y(d[p]) })
				.layer.add(pv.Area)

			vis.render()
		} end

		if @account.closes
			p do
				text "Closes account "
				a(@account.closes.id, :href=>R(AccountShow, @acount.closes))
			end
		end
		if @account.closed_by
			p do
				text "Closed by account "
				a(@account.closed_by.id, :href=>R(AccountShow, @acount.closed_by))
			end
		end
		entries = @account.entries
		if(context.starts and context.ends)
			entries = entries.where(['coalesce(txn_items.date, txns.date) >= ? and coalesce(txn_items.date, txns.date) <= ?', context.starts, context.ends])
		end
		entries = entries.where(['memo ilike ? or payee ilike ?', "%#{@input._q}%", "%#{@input._q}%"]) if @input._q and !@input._q.empty?
		p do
			a("Unreconciled", href: '#first-unrec')
		end
		table do
			thead do
				tr do
					th 'Date'
					th ''
					th 'Memo'
				end
				tr do
					th 'Date'
					th 'Number'
					th 'Account'
					th 'Debit'
					th 'Credit'
					th 'Balance'
					th 'Status'
				end
			end
			first = true
			entries.each do |e|
				_txn(e, @account) do |m|
					if(e.status != 'Reconciled')
						if first
							m.a('', name: "first-unrec")
							first = !first
						end
					end
				end
			end
		end
		div.controls do
			if entries.count > LEDGER_LINES
				if (@input.page ? @input.page.to_i * LEDGER_LINES : 0) > LEDGER_LINES
					a('Back', :href => R(AccountShow, @account.id, :page => @input.page.to_i - 1))
				else
					text('Back')
				end
				text ' '
				if (@input.page ? @input.page.to_i * LEDGER_LINES + LEDGER_LINES : LEDGER_LINES) < entries.count
					a('Next', :href => R(AccountShow, @account.id, :page => @input.page.to_i + 1))
				else
					text('Next')
				end
			end
		end
	end

	def _txn(e, contextacct = nil) 
		tbody.Txn("data-url" => R(Transaction, @account.id, e.id), 'id' => "Txn/#{e.id}") do
			tr do
				td.date('data-field' => 'date') { e.txn.date.strftime('%Y-%m-%d') }
				td ''
				td.memo('data-field' => 'memo', 'colspan' => 5) { e.txn.memo || ' ' }
			end

			e.txn.items.sort_by { |e| e.amount > 0 ? [0, e.account.description] : [1, e.account.description] }.each do |i|
				tr.TxnItem("data-account_id" => i.account_id, "data-association" => 'items', "data-id" => i.id, "data-class" => "TxnItem") do
					td.date('data-field' => 'date') { i.date }
					td.number('data-field' => 'number') { i.number }
					td.account('data-field' => 'account_id') { '&nbsp;'*5 + "#{i.account.description} #{if i.account.account_type then "(#{i.account.account_type})" end}" }
					td.debit('data-field' => 'debit') { i.amount > 0 ? i.amount.abs : '' }
					td.credit('data-field' => 'credit') { i.amount < 0 ? i.amount.abs : '' }
					if contextacct and i.account == contextacct
						td.balance { contextacct.balance(e) } 
					else
						td.balance { }
					end
					td.status('data-field' => 'status') do
						i.status
					end
					td.other do
						yield self
					end
				end
			end
		end
	end

	def accountlist_with_contacts
		ul do 
			@accounts.each do |e|
				c = e.contact
				if c
					li do
						a(c.name || '(no name)', :href=> R(CustomerOverview, e.id))
						text(" #{c.first} #{c.last} #{c.company} ") 
						#send(which, e)
					end
				else
					li do
						a(e.description || '(no name)', :href => R(AccountShow, e))
					end
				end
			end
			#li { a('Add customer', :href => R(ContactEdit, 'new')) }
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

			items = @account.invoices.select { |i| i.status != 'Closed' } + @account.entries
			@input.each_pair do |filter, value|
				items = items.select { |i| if i.respond_to? filter then i.send(filter).to_s == value else true end }
			end

			items.sort_by do |e|
				case e 
				when Elf::Models::TxnItem
					[e.date || e.txn.date, e.txn.id]
				else
					[e.date, 0]
				end
			end.each do |t|
				case t
				when Elf::Models::TxnItem
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
						td (t.date || t.txn.date).strftime('%Y-%m-%d')
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
