module Elf::Models
	class Vendor < Base
		belongs_to :account
		belongs_to :expense_account, :class_name => 'Account', :foreign_key => 'expense_account_id'
	end
end
