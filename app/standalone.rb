#!/usr/bin/env ruby
$LOAD_PATH.unshift 'app'
$LOAD_PATH.unshift 'lib'

Encoding.default_internal = Encoding.default_external=  "UTF-8" 

require 'yaml'
require 'elf'

$config = YAML.load_file(File.join(File.dirname(__FILE__), '..', 'db.yaml'))

ActiveRecord::Base.establish_connection(
	adapter: 'postgresql', 
	host: $config['host'], 
	username: $config['username'], 
	password: $config['password'], 
	database: $config['database']
)

$dbh = ActiveRecord::Base.connection.connection
Elf::DatabaseObject.dbh = $dbh

Paypal = Elf::Account.find 1525
Expenses = Elf::Account.find 1289
Bank = Elf::Account.find 1297
Adjustments = Elf::Account.find 1667
Dividends = Elf::Account.find 2051
Fees = Elf::Account.find 1547
Undeposited = Elf::Account.find 1296
CreditCards = Elf::Account.find 1522
