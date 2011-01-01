function modelForElement(obj) {
	var o = {}
	jQuery(obj).find('[data-field]').not(jQuery(obj).find('[data-association]').find('[data-field]')).each(function(n, e) {
		o[e.dataset.field] = jQuery(e).find('[name='+e.dataset.field+']').val()
	})
	jQuery(obj).find('[data-association]').not('[data-association] [data-association]').each(function(n, e) {
		if(!o[e.dataset.association]) o[e.dataset.association] = []
		o[e.dataset.association].push(modelForElement(e))
	})
	return o
}

jQuery('document').ready( function() {
	var current
	var active
	jQuery('.Txn').dblclick(function(ev) {
		ev.preventDefault()
		var restore = function(ev) {
			if(ev.target.tagName == 'INPUT' || ev.target.tagName == 'SELECT') return;
			if(ev) ev.preventDefault()
			if(!jQuery(this).data('saving')) {
				jQuery(this).data('saving', true)

				// Put a spinner over the saving record and disable its inputs
				jQuery(this).find('input,select').attr('disabled', 'disabled');
				var d = jQuery(document.createElement('div'))
				d.text('Saving...')
				d.addClass('ajax-status')
				jQuery('.navigation').children().last().before(d)

				var data = JSON.stringify(modelForElement(this))
				// Then call this in the callback from the AJAX save
				// Possibly, replace current with the response from the AJAX server

				jQuery.ajax({url: this.dataset.url, type: 'PUT', contentType: 'application/json', processData: false, data: data, success: function() {
					current.show()
					active.remove()
					current = null
					active = null
					d.remove()
				}})
			}
		}
	
		if(current) restore()
		current = jQuery(this)
		active = current.clone()
		active.find('[data-field]').contents().replaceWith(function(i) {
			var f = this.parentNode.dataset.field
			if(f == 'debit' || f == 'credit' || f == 'number' || f == 'memo') {
				var t = document.createElement("input")

				t.setAttribute('name', f)
				t.setAttribute('type', 'text')
				t.value = this.data.trim()
				return t
			} else if(f == 'date') {
				var t = document.createElement('input')
				t.setAttribute('name', this.parentNode.dataset.field)
				t.setAttribute('type', 'date')
				t.value = this.data.trim().replace(/\//g, '-')
				jQuery(t).datepicker({dateFormat: 'yy-mm-dd'})
				return t
			} else if(f == 'account') {
				var t = accountList.cloneNode(true)
				t.setAttribute('name', this.parentNode.dataset.field)
				t.value = jQuery(this).closest('.TxnItem').get(0).dataset.account
				return t
			}

		})
		current.hide().after(active)
		active.dblclick(restore)
	})
})

var accountList

function buildAccountListElement(data) {
	accountList = document.createElement('select')
	for(e in data) {
		var g = document.createElement('optgroup')
		g.setAttribute('label', e)
		data[e].forEach(function(e) {
			var o = document.createElement('option')
			o.innerText = e.account.description
			o.setAttribute('value', e.account.id)
			g.appendChild(o)
		})
		accountList.appendChild(g)
	}
}

var l
if(l = localStorage.getItem('accountList')) {
	buildAccountListElement(JSON.parse(l))
} else {
	buildAccountListElement([])
}

if(!l || localStorage.getItem('accountListMTime') < ((new Date()).valueOf() - 360000)) {
	console.log('updating accountList')
	jQuery.ajax(
		{url: '/accounts/all', beforeSend: function(xhr, settings) {
			xhr.setRequestHeader('Accept', 'application/json')
			return true
		}, success: function(data) {
			buildAccountListElement(data)
			localStorage.setItem('accountList', JSON.stringify(data))
			localStorage.setItem('accountListMTime', (new Date()).valueOf())
		}, dataType: 'json'
	})
}
