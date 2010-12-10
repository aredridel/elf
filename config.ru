$LOAD_PATH.unshift 'lib'
$LOAD_PATH.unshift 'app'

require 'camping'
require 'elf'
require 'active_record'

$config = YAML.load_file(File.join(File.dirname(__FILE__), 'db.yaml'))

ActiveRecord::Base.establish_connection(:adapter => 'postgresql', :host => $config['host'], :username => $config['username'], :password => $config['password'], :database => $config['database'])

use Rack::ShowExceptions

run Elf
