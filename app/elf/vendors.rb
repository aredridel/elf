# encoding: utf-8

module Elf::Controllers

	class VendorBillShowAttachment < R '/vendors/(\d+)/bills/(\d+)/attachments/(\d+)'
		def get(vid, bid, aid)
			@vendor = Vendor.find(vid)
			@bill = @vendor.bills.find(bid)
			@att = @bill.attachments.find(aid)
			if(@att.file.content_type =~ %r{^text/})
				return @att.file.data
			else
				@headers['Content-Type'] = @att.file.content_type
				return @att.file.data
			end
		end
	end

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
				b.due = @input.due
				t = Txn.new
				t.date = @input.date
				t.ttype = 'Misc'
				e1 = TxnItem.new(:amount => amount * -1, :account_id => @vendor.account.id)
				t.items << e1
				e2 = TxnItem.new(:amount => amount, :account_id => (@vendor.expense_account ? @vendor.expense_account.id : 1289))
				t.items << e2
				b.txn = t
				b.save!
				# Enter bill, create transaction
			end
			redirect R(VendorOverview, @vendor.id)
		end
	end

	class VendorBillAttach < R '/vendors/(\d+)/bills/(\d+)/attach'
		def get(vid, bid)
			@vendor = Vendor.find(vid)
			@bill = @vendor.bills.find(bid)
			render :vendorbillattach
		end
		def post(vid, bid)
			@vendor = Vendor.find(vid)
			@bill = @vendor.bills.find(bid)
			@bill.attachments << FileAttachment.new(:file => Models::File.new(:data => @input.file[:tempfile].read, :filename => @input.file[:filename], :content_type => @input.file[:type]))
			@bill.save!
			redirect R(VendorShowBill, @vendor, @bill)

		end
	end

	class VendorListBills < R '/vendors/(\d+)/bills'
		def get(vid)
			@vendor = Vendor.find(vid)
			@bills = @vendor.bills.order('date').select { |b| !b.payment }
			render :vendorlistbills
		end
	end

	class VendorPayBill < R '/vendors/(\d+)/bills/(\d+)/pay'
		def get(vid, bill)
			@vendor = Vendor.find(vid)
			@bill = @vendor.bills.find(bill)
			render :vendorpaybill
		end
	end

	class VendorShowBill < R '/vendors/(\d+)/bills/(\d+)'
		def get(vid, bill)
			@vendor = Vendor.find(vid)
			@bill = @vendor.bills.find(bill)
			render :vendorshowbill
		end
	end

	class VendorHistory < R '/vendors/(\d+)/history'
		def get(vid)
			@vendor = Company.find(1).vendors.find(vid)
			@page_title = "History for vendor #{@vendor.name}"
			@account = @vendor.account
			render :accounthistorydetail
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
		belongs_to :company
		has_many :bills
	end

	class Bill < Base
		belongs_to :vendor
		belongs_to :txn
		belongs_to :payment, :class_name => 'Txn', :foreign_key => 'payment_txn_id'
		def amount
			txn.amount
		end

		has_many :attachments, :as => :attachment, :class_name => 'Elf::Models::FileAttachment'
	end

	class File < Base
		has_many :attachments, :class_name => 'Elf::Models::FileAttachment'
	end

	class FileAttachment < Base
		belongs_to :file
		belongs_to :attachment, :polymorphic => true
	end
	
end

module Elf::Views
	def vendoraddbill
		h1 "Add bill from #{@vendor.name}"
		form :action => R(VendorAddBill, @vendor.id), :method => 'post' do
			table do
				tr do
					td { label(:for => 'date') { 'Date' } }
					td { input :type => 'date', :name => 'date', :value => Time.now.strftime('%Y/%m/%d') }
				end
				tr do
					td { label(:for => 'due') { 'Due' } }
					td { input :type => 'date', :name => 'due' }
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

	def vendorlistbills
		ul do
			@bills.each do |b|
				li do
				       	a(b.date.to_s, :href => R(VendorShowBill, b.vendor, b))
					text ' '
					a('Pay', :href => R(VendorPayBill, b.vendor, b))
				end 
			end
		end
	end

	def vendorshowbill
		text "Date: " + @bill.date.strftime('%Y-%m-%d')
		text @bill.inspect + @bill.txn.inspect + @bill.txn.items.inspect
		a 'Attach', :href => R(VendorBillAttach, @vendor, @bill)
		h2 'Attachments'
		ul do
			@bill.attachments.each do |att|
				li do 
					a att.file.filename, :href => R(VendorBillShowAttachment, @vendor, @bill, att)
				end
			end
		end
	end

	def vendorbillattach
		form :action => R(VendorBillAttach, @vendor, @bill), :method => 'post', :enctype => 'multipart/form-data' do
			input :type=>:file, :name => 'file'
			input :type => 'submit', :value => 'upload'
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

	def vendorpaybill
		
	end

	def vendoroverview
		if @vendor.contact
			_contact(@vendor.contact)
		else
			text 'No contact information'
		end
		p "Current Balance: $#{@vendor.account.balance}"
		p.screen do
			a 'History', :href => R(VendorHistory, @vendor.id)
			text ' '
			a 'Pay', :href => R(VendorListBills, @vendor.id) 
			text ' '
			a 'Edit', :href => R(ContactEdit, @vendor.contact_id || 'new') # FIXME -- connect the new record
			text ' '
			a 'Add Bill', :href => R(VendorAddBill, @vendor.id)
		end
	end
end
