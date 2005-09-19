require 'shared_setup'

logger = Logger.new(STDOUT)

# Database setup ---------------

logger.info "\nCreate tables"

[ "DROP TABLE companies", "DROP TABLE people", 
  "CREATE TABLE companies (id int(11) auto_increment, client_of int(11), name varchar(255), type varchar(100), PRIMARY KEY (id))",
  "CREATE TABLE people (id int(11) auto_increment, name text, company_id text, PRIMARY KEY (id))"
].each { |statement|
  begin; ActiveRecord::Base.connection.execute(statement); rescue; end # Tables doesn't necessarily already exist
}


# Class setup ---------------

class Company < ActiveRecord::Base
  has_many :people, :class_name => "Person"
end

class Firm < Company
  has_many :clients, :foreign_key => "client_of"

  def people_with_all_clients
    clients.inject([]) { |people, client| people + client.people }
  end
end

class Client < Company
  belongs_to :firm, :foreign_key => "client_of"
end

class Person < ActiveRecord::Base
  belongs_to :company

  def table_name() "people" end
end


# Usage ---------------

logger.info "\nCreate fixtures"
firm = Firm.new("name" => "Next Angle")
firm.save

client = Client.new("name" => "37signals", "client_of" => firm.id)
client.save


logger.info "\nUsing Finders"

next_angle = Company.find(1)
next_angle = Firm.find(1)    
next_angle = Company.find_first "name = 'Next Angle'"
next_angle = Firm.find_by_sql("SELECT * FROM companies WHERE id = 1").first

Firm === next_angle


logger.info "\nUsing has_many association"

next_angle.has_clients?
next_angle.clients_count
all_clients = next_angle.clients

thirty_seven_signals = next_angle.find_in_clients(2)


logger.info "\nUsing belongs_to association"

thirty_seven_signals.has_firm?
thirty_seven_signals.firm?(next_angle)