$:.unshift(File.join(File.dirname(__FILE__), 'lib'))
require 'kansas'

db = KSDatabase.new('dbi:Pg:theinternetco.net:db.theinternetco.net', 'dev.theinternetco.net', 'asd123')
db.table(:Customers, :customers)
db.table(:Accounts, :accounts)
db.table(:Services, :services)
db.table(:Phones, :phones)
db.select(:Customers, :Services, :Phones) do |c,s,p|
	((c.cardexpire < c._now) & c.cardexpire.is_not_null & (c.id == s.customer_id) & (c.id == p.customer_id))
end.each do |c,s|
	puts "#{c.name}\t#{c.cardexpire}\t#{s.name}"
end


