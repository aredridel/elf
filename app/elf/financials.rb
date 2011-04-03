
module Elf::Helpers
	def load_reporting_accounts
		company = Elf::Company.find 1
		accounts = company.accounts
		groups = accounts.of("Expense").map { |e| e.account_group }.sort.uniq
		otherexpense = {}
		groups.each do |g| 
			otherexpense[g] = accounts.of("Expense").where(account_group: g)
		end
		@accounts = {
			assets: accounts.assets("Assets"),
			cash: accounts.assets("Cash"),
			receivable: accounts.assets("Receivable"),
			payable: accounts.of("Liability").where(account_group: "Payable"),
			income: accounts.of("Liability").where(account_group: "Income"),
			stdexpenses: accounts.of("Expense").where(account_group: "Expense"),
			otherexpense: otherexpense,
			revenue: accounts.of("Income"),
			equity: accounts.of("Equity"),
			intangible: accounts.find(6606),
			amortization: accounts.find(6607),
		}
		
	end
end

module Elf::Controllers
	class BalanceSheet < R('/financials/balance(/full)?')
		def get(full)
			load_reporting_accounts
			render :balance_sheet, full
		end
	end

	class F1120 < R("/financials/1120")
		def get
			load_reporting_accounts
			render :f1120
		end
	end

	class IncomeReport < R ('/financials/income')
		def get
			load_reporting_accounts
			render :income_report
		end
	end
end

module Elf::Helpers
	def balance_table(accounts, full = false)
		table do
			if full
				accounts.each do |b|
					bal = b.balance(context.ends)
					next if bal == Money.new(0)
					tr do
						td b.description
						td b.balance(context.ends)
					end
				end
				tr do
					th "Total"
					td accounts.balance(context.ends)
				end
			else
				tr do
					td "Total"
					td accounts.balance(context.ends)
				end
			end
		end
	end
end

module Elf::Views
	def balance_sheet(full = false)
		h1 'Balance Sheet ' + context.starts.strftime("%Y/%m/%d") + ' to ' + context.ends.strftime("%Y/%m/%d")
		h2 'Assets'
		h3 'Current Assets'
		balance_table(@accounts[:assets], full)
		h3 'Cash and Bank Accounts'
		balance_table(@accounts[:cash], full)
		h3 'Accounts Receivable'
		balance_table(@accounts[:receivable], false)
		h4 'Less: Allowances for Doubtful Accounts'
		p { @accounts[:receivable].balance(context.ends) * 0.05 }

		p { "Total Assets: " + (@accounts[:assets].balance(context.ends) + @accounts[:cash].balance(context.ends) + @accounts[:receivable].balance(context.ends) - (@accounts[:receivable].balance(context.ends) * 0.05)).to_s }
		#h3 'Inventories'
		#h3 'Prepaid Expenses'
		#Investment Securities (Held for trading)
		#Other Current Assets
		#Non-Current Assets (Fixed Assets)
		#Property, Plant and Equipment (PPE) 
		#  Less : Accumulated Depreciation 
		#Investment Securities (Available for sale/Held-to-maturity)
		#Investments in Associates
		#h3 'Intangible Assets (Patent, Copyright, Trademark, etc.)'
		h3 'Goodwill'
		p { @accounts[:intangible].balance(context.ends) }
		h4 ' Less : Accumulated Amortization'
		p { @accounts[:intangible].balance(context.ends) - @accounts[:amortization].balance(context.ends) }
		#Other Non-Current Assets, e.g. Deferred Tax Assets, Lease Receivable

		h2 'Liabilities and Equity'
		h3 'Current Liabilities'
		h4 'Accounts Payable'
		p { @accounts[:payable].balance(context.ends) }
		#Current Income Tax Payable
		#Current portion of Loans Payable
		#Short-term Provisions
		#Other Current Liabilities, e.g. Unearned Revenue, Deposits

		#Non-Current Liabilities (Creditors: amounts falling due after more than one year)
		#Loans Payable
		#Issued Debt Securities, e.g. Notes/Bonds Payable
		#Deferred Tax Liabilities
		#Provisions, e.g. Pension Obligations
		#Other Non-Current Liabilities, e.g. Lease Obligations 
		
		h3 'Shareholders Equity'
		h4 'Paid-in Capital'
		p { @accounts[:equity].balance(context.ends) }
		#  Share Capital (Ordinary Shares, Preference Shares)
		#  Share Premium
		#  Less: Treasury Shares
		#Retained Earnings
		#Revaluation Reserve
		#Accumulated Other Comprehensive Income
		 
		#Non-Controlling Interest
	end

	def f1120
		h1 'Form 1120 Inputs - Income and Expense Report ' + context.starts.strftime("%Y/%m/%d") + ' to ' + context.ends.strftime("%Y/%m/%d")
		h2 'Assets'
		p { "Total Assets: " + (@accounts[:assets].balance(context.ends) + @accounts[:cash].balance(context.ends) + @accounts[:receivable].balance(context.ends) - (@accounts[:receivable].balance(context.ends) * 0.05)).to_s }
		h2 'Revenues'
		h3 'Gross Revenues'
		balance_table(@accounts[:revenue], true) 

		refunds = company.accounts.find(1546).balance(context.ends)
		p { "Returns and Allowances: #{refunds}" }
		p { "Net: #{@accounts[:revenue].balance(context.ends) - refunds}" }
		cogs = company.accounts.find(6600).balance(context.ends)
		p { "COGS: #{cogs}" }
		p { "Gross Profit: #{@accounts[:revenue].balance(context.ends) - refunds - cogs }" }

		h2 'Expenses'
		h3 'Standard Expenses'
		balance_table(@accounts[:stdexpenses], true) 
		@accounts[:otherexpense].keys.each do |k|
			h3 "#{k} Expenses"
			balance_table(@accounts[:otherexpense][k], true) 
		end

	end

	def income_report
		h1 'Income and Expense Report ' + context.starts.strftime("%Y/%m/%d") + ' to ' + context.ends.strftime("%Y/%m/%d")
		h2 'Revenues'
		h3 'Gross Revenues'
		balance_table(@accounts[:revenue], true) 

		h2 'Expenses'
		h3 'Standard Expenses'
		balance_table(@accounts[:stdexpenses], true) 
		@accounts[:otherexpense].keys.each do |k|
			h3 "#{k} Expenses"
			balance_table(@accounts[:otherexpense][k], true) 
		end

	end
end
