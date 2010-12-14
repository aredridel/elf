# encoding: utf-8

module Elf::Controllers
	class VendorAddBill < R '/vendors/(\d+)/newbill'
		def get(id)
			@vendor = Vendor.find(id.to_i)
			render :vendoraddbill
		end

		def post(id)
			@vendor = Vendor.find(id.to_i)
			amount = Money.new(BigDecimal.new(@input.amount) * 100)
			Vendor.transaction do
				b = Bill.new
				b.date = @input.date
				b.vendor_id = @vendor.id
				t = Txn.new
				t.date = @input.date
				t.ttype = 'Misc'
				t.create
				e1 = TxnItem.new(:amount => amount * -1, :account_id => @vendor.account.id)
				t.items << e1
				e2 = TxnItem.new(:amount => amount, :account_id => (@vendor.expense_account ? @vendor.expense_account.id : 1289))
				t.items << e2
				e1.create
				e2.create
				b.transaction_id = t.id
				b.create
				# Enter bill, create transaction
			end
			redirect R(VendorOverview, @vendor.id)
		end
	end

	class VendorFinder < R '/vendors/find'
		def get
			@page_title = "Vendors matching \"#{@input.q}\""
			search = @input.q
			@results = Elf::Vendor.find(:all, :conditions => ["name ilike ?", *(["%#{@input.q}%"])])
			render :vendorlist
		end
	end

	class VendorOverview < R '/vendors/(\d+)'
		def get(id)
			@vendor = Vendor.find(id.to_i)
			@page_title = 'Vendor — ' + @vendor.name
			render :vendoroverview
		end
	end
end

module Elf::Models
	class Vendor < Base
		belongs_to :account
		belongs_to :contact
		belongs_to :expense_account, :class_name => 'Account', :foreign_key => 'expense_account_id'
	end
end

module Elf::Views
	def vendoraddbill
		h1 "Add bill from #{@vendor.name}"
		form :action => R(VendorAddBill, @vendor.id), :method => 'post' do
			table do
				tr do
					td { label(:for => 'date') { 'Date' } }
					td { input :type => 'text', :name => 'date', :value => Time.now.strftime('%Y/%m/%d') }
				end
				tr do
					td { label(:for => 'amount') { 'Amount' } }
					td { input :type => 'text', :name => 'amount' }
				end
				tr do
					td { label(:for => 'number') { 'Number' } }
					td { input :type => 'text', :name => 'number' }
				end
				tr do
					td { }
					td { input :type => 'submit', :value => 'Save' }
				end
			end
		end
	end

	def vendorlist
		ul do 
			@results.each do |e|
				li do
					a(e.name , :href=> R(VendorOverview, e.id))
				end
			end
		end
	end

	def vendoroverview
		if @vendor.contact
			_contact(@vendor.contact)
		else
			text 'No contact information'
		end
		p "Current Balance: $#{@vendor.account.balance}"
		p.screen do
			a 'History' # FIXME
			text ' '
			a 'Pay' # FIXME
			text ' '
			a 'Add Bill', :href => R(VendorAddBill, @vendor.id)
		end
	end
end
