require 'camping'
require 'elf/models'
require 'basic_authentication'

Camping.goes :ElfUser

module ElfUser
	include Camping::BasicAuth

	def self.authenticate(u, p)
		u == 'rick'
	end

	module Controllers

		class CreditCardPay < R('/payment')
			def get
				@page_title = 'Charge to card'
				@customer = Customer.find(:first, :conditions => ['name = ?', @username])
				render :creditcardpay
			end
			def post
				@customer = Customer.find(:first, :conditions => ['name = ?', @username])
				amount = Money.new(BigDecimal.new(@input.amount) * 100)
				if amount <= @customer.account.balance
					response = @customer.charge_card(amount)
					if response.success?
						redirect R(Index)
					else
						raise StandardError, response.message
					end
				else
					@error = 'Amount must be less than your balance'
					render :error
				end
			end
		end

		class Index < R '/'
			def get
				@page_title = 'Customer Account'
				@customer = Customer.find(:first, :conditions => ['name = ?', @username])
				if !@customer
					render :nocustomer
				else
					render :index
				end
			end
		end

		class Style < R '/(.*\.css)'
			def get(file)
				@headers['Content-Type'] = 'text/css'
				@body = File.read(File.join(File.dirname(__FILE__), file))
			end
		end

	end

	module Models
		include Elf::Models
	end

	module Views
		def error
		end

		def creditcardpay
			form :action => R(CreditCardPay), :method => 'POST' do
				p do
					text "Charge "
					input :type => 'text', :name => 'amount', :value => @customer.account.balance, :size => 6
					text " to card *#{@customer.cardnumber[-4..-1]}?"
				end
				input :type => 'submit', :value => "Charge"
			end
		end

		def index
			p @customer.account_name
			p do 
				self << "Balance: #{@customer.account.balance.format} "
				if customer.account.balance > Money.new(0)
					a('Pay by credit card', :href => R(CreditCardPay))
				end
			end
		end

		def layout
			xhtml_strict do
				head do
					title "#{@page_title || ''}"
					link :rel => 'Stylesheet', :href=> '/site.css', :type => 'text/css'
				end
				body do
					h1 @page_title if @page_title
					self << yield
				end
			end
		end

		def nocustomer
			h1 "Not found"
			p "The user you're logging in as is not in our customer database."
		end
	end
end

class Money
  def format(*rules)
    rules = rules.flatten

    if rules.include?(:no_cents)
      formatted = sprintf("$%d", cents.to_f / 100  )          
    else
      formatted = sprintf("$%.2f", cents.to_f / 100  )      
    end

    if rules.include?(:with_currency)
      formatted << " "
      formatted << '<span class="currency">' if rules.include?(:html)
      formatted << currency
      formatted << '</span>' if rules.include?(:html)
    end
    formatted
  end
end

$config = YAML.load_file(File.join(File.dirname(__FILE__), 'db.yaml'))

ActiveRecord::Base.establish_connection(:adapter => 'postgresql', :host => $config['host'], :username => $config['username'], :password => $config['password'], :database => $config['database'])
