require 'csv' 
CSV.open(ARGV[0], 'r', "\t") do |row|
	h = {
		"Response" => row[0].to_i,
		"Amount" => row[9].to_f,
		"Customer ID" => row[12], 
		"Invoice" =>  row[7], 
		"Date/Time" => row[4] 
	}

	if h["Customer ID"] and h["Response"] == 1
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

