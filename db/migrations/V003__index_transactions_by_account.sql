-- An account's statement reads its transactions newest first.
-- Without this index, every statement scans all of TRANSACTIONS.
CREATE INDEX ix_transactions_account_date ON transactions (account_id, txn_date);