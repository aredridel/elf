jQuery('document').ready( function() {
	var current
	jQuery('.Txn').dblclick(function(ev) {
		ev.preventDefault()
		current = jQuery(this)
		var n = current.clone()
		n.find('.debit,.credit').contents().replaceWith(function(i,h) {
			var t = document.createElement("input")
			t.value = this.data.trim()
			return t
		})
		current.hide().after(n)
		n.dblclick(function(ev) {
			ev.preventDefault()
			current.show()
			n.remove()
		})
	})
})
