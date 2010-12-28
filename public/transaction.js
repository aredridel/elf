jQuery('document').ready( function() {
	var current
	jQuery('.Txn').dblclick(function(ev) {
		ev.preventDefault()
		current = jQuery(this)
		var n = current.clone()
		n.find('.debit,.credit,.number,.memo').contents().replaceWith(function(i) {
			var t = document.createElement("input")
			t.setAttribute('name', this.parentNode.getAttribute('class'))
			t.setAttribute('type', 'text')
			t.value = this.data.trim()
			return t
		})
		n.find('.date').contents().replaceWith(function(i) {
			var t = document.createElement('input')
			t.setAttribute('name', this.parentNode.getAttribute('class'))
			t.setAttribute('type', 'date')
			t.value = this.data.trim().replace(/\//g, '-')
			return t
		})
		n.find('.account').contents().replaceWith(function(i) {
			var t = document.createElement('select')
			t.setAttribute('name', this.parentNode.getAttribute('class'))
			var o = document.createElement('option')
			o.innerText = 'Test'
			t.appendChild(o)
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
