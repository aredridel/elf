
module Elf::Models
	class Deposit < Base
		has_many :deposit_items
		has_many :txns, :through => :deposit_items
		belongs_to :txn

		def amount
			txns.map do |t|
				t.items.map do |e|
					if e.account.id == Elf::Company.find(1).undeposited_funds_account.id
						e.amount
					else
						Money.new(0)
					end
				end
			end.flatten.inject(Money.new(0)) { |a,e| a+e }
		end
	end

	class DepositItem < Base
		belongs_to :deposit
		belongs_to :txn
	end

	class Txn < Base
		has_one :deposit_item
		has_one :deposit, :through => :deposit_item
	end
end

module Elf::Controllers
	class DepositRecord < R '/deposits/record'
		def get
			@page_title = 'Record Deposit'
			@entries = Elf::Company.find(1).undeposited_funds_account.entries.find(:all, :conditions => 'txns.id not in (select txn_id from deposit_items)')
			render :deposit_record

		end
		def post
			@deposit = Deposit.new
			@deposit.date = Time.parse(@input.date)
			@input.txn_id.each do |id|
				txn =  Elf::Txn.find(id)
				raise "Txn already deposited" if(txn.deposit)
				@deposit.txns << txn
			end

			@deposit.save

			redirect R(DepositRecord)
		end
	end

end

module Elf::Views
	def deposit_record
		h1 'Prepare deposit'
		form :action => R(DepositRecord), :method => 'POST' do
			table do
				@entries.each do |e|
					tr do
						td.controls { input(:name => 'txn_id[]', :type => 'checkbox', :value => e.txn.id ) }
						td { e.txn.number || '' }
						td { e.txn.memo || '' }
						td { e.amount.to_s }
					end
				end
			end
			label do
				self << "Date:"
				input :name=>'date', :type=>"date", :value => Time.now.strftime('%Y-%m-%d')
			end
			input :type => 'submit', :value => "Record Deposit"
		end
	end
end
