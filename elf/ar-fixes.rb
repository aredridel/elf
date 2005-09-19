# elf/ar-fixes.rb $Id:$
#
# * Aredridel <aredridel@nbtsc.org> 2005-03-31


class << ActiveRecord::Base
	def aggregate(sym, &block)
		sym = sym.intern
		@aggregates ||= Hash.new
		@aggregates[sym] = block
	end
	def aggregates
		@aggregates ||= Hash.new
		@aggregates
	end
end

class ActiveRecord::Base
	def list_data
		return {}
	end
end


