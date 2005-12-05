# elf/utility.rb $Id:$
#
# * Aredridel <aredridel@nbtsc.org> 2005-03-31

class Class
	def basename
		name.sub(/^.*::/, '')
	end
end

class Hash
	def symbolize_strings!
		each_pair do |k,v|
			self[k.intern] = v if k.kind_of? String
		end
	end
end

class String
	def plural
		if /s$/ =~ self
			self
		elsif /y$/ =~ self
			self.sub(/y$/, 'ies')
		else
			self + 's'
		end
	end
end

module URI
	class HTTP
		class QueryString
			def initialize(s)
				@s = s
				@h = Hash.new { |h,k| h[k] = Array.new }
				if s
					s.split('&').map{|e| e.split('=')}.each {|n| @h[n[0]] << n[1] }
				end
			end
			def to_s
				if !empty?
					"?#{@s}"
				else
					""
				end
			end
			def [](k)
				@h[k]
			end
			def []=(k,v)
				@h[k] = v
			end
		end
	end
end

