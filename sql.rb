module SQL
	class Error < RuntimeError
	end

	class Tuple
		def initialize
		end
		
		def self.table
			self.name.downcase << "s"
		end

		attr_writer :database

		def update
			if primarykey
				$stderr.puts "Updating object"
				q = "UPDATE #{self.class.table} SET " << self.class.fields.map { |f| "#{f} = '#{self.send f.intern}'" }.join(", ") << " WHERE #{self.class.keyfield} = '#{primarykey}'"
				$stderr.puts "Update is: #{q}"
				@database.query q
			else
				raise Error.new("No primary key for object")
			end
		end

		def self.keyfield
			real_fields[0]
		end

		attr_reader :primarykey

		def setup(tuple)
			@primarykey = tuple[self.class.keyfield]
			tuple.each do |k,v|
				send "#{k}=".intern, v
			end
		end

		def store database
			database.query "INSERT INTO #{self.class.table} (" <<
				self.class.real_fields.select {|f| !self.send(f.intern).nil? }.join(",") << 
			") VALUES (" << 
				self.class.real_fields.select {|f| !self.send(f.intern).nil? }.map {|f| "'#{self.send(f.intern)}'"}.join(", ") <<
			")"
		end
	end

	class List
		include Enumerable
		def initialize(klass, result, db)
			@klass = klass
			@result = result
			@database = db
		end

		def size
			@result.num_rows
		end

		alias :length :size

		def first
			return nil if length <= 0
			h = @result.fetch_hash
			o = @klass.new
			o.database= @database
			o.setup(h)
			o
		end
		
		def each
			$stderr.puts "Enumerating list"
			@result.each_hash do |h|
				o = @klass.new
				o.setup(h)
				yield o
			end
		end
	end

	class Database
		def initialize(host, user, pass, db)
				@database = Mysql::new(host,user,pass,db)
		end
		def ask(klass, filter = nil)
			if filter.nil?
				q = ''
			else
				cl = []
				filter.keys.each do |f|
					s = f.to_s
					cl << "#{s} = '#{filter[f]}'"
				end
				if cl.empty? 
					cl = ''
				else
					cl = "WHERE " << cl.join(' AND ') 
				end
			end
			q = "SELECT DISTINCT #{klass.real_fields.join(',')} FROM #{klass.table} #{cl}"
			$stderr.puts "querying #{q}"
			List.new(klass, @database.query(q), self)
		end

		def get(klass, key)
			$stderr.puts "Loading object"
			o = klass.new
			res = @database.query "SELECT #{klass.real_fields.join ","} FROM #{klass.table} WHERE #{klass.keyfield} = '#{key}'"
			h = res.fetch_hash
			if h.nil?
				return nil
			else
				o.setup h
				o.database= self
				return o
			end
		end

		def query(q)
			# FIXME: make put method instead
			$stderr.puts "Querying #{q}"
			@database.query(q)
		end
	end
end
 
