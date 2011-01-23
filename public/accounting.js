function modelForElement(obj, newRecord) {
	var o = {}
	if(obj.dataset.id && !newRecord) o.id = obj.dataset.id
	jQuery(obj).find('[data-field]').not(jQuery(obj).find('[data-association]').find('[data-field]')).each(function(n, e) {
		o[e.dataset.field] = jQuery(e).find('[name='+e.dataset.field+']').val()
	})
	jQuery(obj).find('[data-association]').not('[data-association] [data-association]').each(function(n, e) {
		if(!o[e.dataset.association]) o[e.dataset.association] = []
		o[e.dataset.association].push(modelForElement(e, newRecord))
	})
	return o
};

(function() {
var current
var active
TxnStartEdit = function(ev) {
	ev.preventDefault()
	var newRecord = false
	if(ev.ctrlKey) newRecord = true

	var restore = function(ev, next) {
		if(ev) {
			ev.preventDefault()
			if(ev.target.tagName == 'INPUT' || ev.target.tagName == 'SELECT') return;
		}
		if(!jQuery(this).data('saving')) {
			jQuery(this).data('saving', true)

			// Put a spinner over the saving record and disable its inputs
			jQuery(this).find('input,select').attr('disabled', 'disabled');
			var d = jQuery(document.createElement('div'))
			d.text('Saving...')
			d.addClass('ajax-status')
			jQuery('.navigation').children().last().before(d)

			var data = JSON.stringify(modelForElement(this, newRecord))

			// Possibly, replace current with the response from the AJAX server
			var req = {}
			req.url = jQuery(this).attr('data-url')
			req.type = 'PUT'
			req.contentType = 'application/json'
			req.processData = false
			req.data = data
			req.context = this
			if(newRecord) {
				req.url = '/txns'
				req.type='POST'
			}
			req.success = function(newData) {
				current.before(newData)
				current.prev().dblclick(TxnStartEdit)
				if(!newRecord) {
					current.remove()
				}
				active.remove()
				current = null
				active = null
				d.remove()
				jQuery(this).data('saving', false)
				if(next) jQuery(next).trigger('dblclick')
			}
			req.error = function() {
				d.remove()
				jQuery(this).data('saving', false)
				jQuery(this).find('input,select').removeAttr('disabled')
			}

			jQuery.ajax(req)
		}
	}

	if(current) {
		restore.apply(active.get(0), [ev, this])
		return
	}
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
		} else if(f == 'account_id') {
			var t = accountList.cloneNode(true)
			t.setAttribute('name', this.parentNode.dataset.field)
			t.value = jQuery(this).closest('.TxnItem').get(0).dataset.account_id
			return t
		}

	})
	if(newRecord) {
		current.after(active)
	} else {
		current.hide().after(active)
	}
	active.dblclick(restore)
}
})()

function HideContextParams() {
	/*

	var s
	if(window.location.search) {
		s = jQuery.deparam(window.location.search.slice(1))
		delete s['contextstart']
		delete s['contextend']
		s = jQuery.param(s)
		s = (s ? '?' + s : '')
	} else {
		s = ''
	}

	window.history.replaceState({}, '', window.location.protocol + '//' +
		window.location.host +
		(window.location.port ? ':'+window.location.port : '') +
		window.location.pathname +
		s +
		window.location.hash)
	*/
}

function AppendContextParams() {
	if(this.href.match(/\?/)) {
		this.href = this.href + '&' + jQuery('#contextdate').serialize()
	} else {
		this.href = this.href + '?' + jQuery('#contextdate').serialize()
	}
}

jQuery('document').ready(function() {
	jQuery('[type=date]').datepicker({dateFormat: 'yy-mm-dd'})
	HideContextParams()
	jQuery('a').click(AppendContextParams)
	jQuery('form').submit(function(ev) {
		var t = jQuery('#contextdate').children().clone()
		t.hide()
		jQuery(this).append(t)
	})
	jQuery('.Txn').dblclick(TxnStartEdit)
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
