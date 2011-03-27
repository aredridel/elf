
module Elf::Controllers
	class BalanceSheet < R('/financials/balance(/full)?')
		def get(full)
			company = Elf::Company.find 1
			accounts = company.accounts
			@accounts = {
				cash: accounts.assets("Cash"),
				receivable: accounts.assets("Receivable"),
				revenue: accounts.of("Liability").where(account_group: "Income")
			}
			
			render :balance_sheet, full
		end
	end

	class IncomeReport < R ('/financials/income')
		def get
			company = Elf::Company.find 1
			accounts = company.accounts
			@accounts = {
				expenses: accounts.of("Expense"),
				revenue: accounts.of("Income"),
			}
			
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
					td accounts.balance(context)
				end
			else
				tr do
					td "Total"
					td accounts.balance(context)
				end
			end
		end
	end
end

module Elf::Views
	def balance_sheet(full = false)
		h1 'Balance Sheet'
		h2 'Assets'
		h3 'Current Assets'
		h3 'Cash and Bank Accounts'
		balance_table(@accounts[:cash], full)
		h3 'Accounts Receivable'
		balance_table(@accounts[:receivable], false)
		h4 'Less: Allowances for Doubtful Accounts'
		#h3 'Inventories'
		#h3 'Prepaid Expenses'
		#Investment Securities (Held for trading)
		#Other Current Assets
		#Non-Current Assets (Fixed Assets)
		#Property, Plant and Equipment (PPE) 
		#  Less : Accumulated Depreciation 
		#Investment Securities (Available for sale/Held-to-maturity)
		#Investments in Associates
		#Intangible Assets (Patent, Copyright, Trademark, etc.)
		#  Less : Accumulated Amortization
		#Goodwill
		#Other Non-Current Assets, e.g. Deferred Tax Assets, Lease Receivable

		h2 'Liabilities and Equity'
		h3 'Current Liabilities'
		h4 'Accounts Payable'
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
		#  Share Capital (Ordinary Shares, Preference Shares)
		#  Share Premium
		#  Less: Treasury Shares
		#Retained Earnings
		#Revaluation Reserve
		#Accumulated Other Comprehensive Income
		 
		#Non-Controlling Interest
	end

	def income_report
		h1 'Income and Expense Report'
		h2 'Revenues'
		h3 'Gross Revenues'
		balance_table(@accounts[:revenue], true) 

		h2 'Expenses'
		balance_table(@accounts[:expenses], true) 
	end
end
