module Elf::Models
	class Attachment < Base
	end
end

module Elf::Controllers
	class Attachments < R '/attachments'
		@attachments = Attachment.find(:all)
	end
end
