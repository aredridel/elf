Dir.open(".").each do |f| 
	h = {}
	if File.file? f
		File.open(f).readlines.grep(/ : /).each do |l| 
			key, val = *l.split(':').map {|e| e.strip }
			h[key] = val.strip
		end 

		if h['Type'] =~ /Credit/
			h['Amount'] = -(h['Amount'].to_f)
		end
		if h['Customer ID'] and h['Response'] =~ /approved/
			puts <<"EOT" 
BEGIN TRANSACTION;
INSERT INTO transactions (memo, date) 
	VALUES ('Credit Card Payment on #{h['Date/Time']} for Invoice ##{h['Invoice']}', now());
INSERT INTO transaction_items (transaction_id, amount, account_id) (SELECT currval('transactions_id_seq'), #{-(h['Amount'].to_f)}, account_id FROM customers WHERE name = '#{h['Customer ID']}');
INSERT INTO transaction_items (transaction_id, amount, account_id) (SELECT currval('transactions_id_seq'), #{h['Amount'].to_f}, 1297);
END TRANSACTION;
EOT
		end
	end
end

