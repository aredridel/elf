
module Elf::Controllers
	class DepositRecord < R '/deposits/record'
		def get
			@page_title = 'Record Deposit'
			@entries = Elf::Company.find(1).undeposited_funds_account.entries
			render :deposit_record

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
						td.controls { input(:type => 'checkbox') }
						td { e.txn.number || '' }
						td { e.txn.memo || '' }
						td { e.amount.to_s }
					end
				end
			end
			label do
				self << "Date:"
				input :name=>'date', :type=>"date"
			end
		end
	end

end
