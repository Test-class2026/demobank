-- Transfers between accounts, and an audit trail of every balance change.
 
CREATE TABLE balance_audit (
    audit_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id   NUMBER        NOT NULL,
    old_balance  NUMBER(15,2)  NOT NULL,
    new_balance  NUMBER(15,2)  NOT NULL,
    changed_by   VARCHAR2(128) NOT NULL,
    changed_at   TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL
);
 
-- Fires for every row whose balance changes, whoever changes it and however
CREATE OR REPLACE TRIGGER trg_accounts_balance_audit
AFTER UPDATE OF balance ON accounts
FOR EACH ROW
WHEN (NEW.balance <> OLD.balance)
BEGIN
    INSERT INTO balance_audit (account_id, old_balance, new_balance, changed_by)
    VALUES (:OLD.account_id, :OLD.balance, :NEW.balance, SYS_CONTEXT('USERENV', 'SESSION_USER'));
END;
/
 
CREATE OR REPLACE PACKAGE bank_pkg AS
    -- Errors the app shows to the user: ORA-20001 to ORA-20006
    e_insufficient_funds EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_insufficient_funds, -20001);
 
    FUNCTION balance_of (p_account IN accounts.account_number%TYPE) RETURN accounts.balance%TYPE;
 
    PROCEDURE transfer_funds (p_from_account IN accounts.account_number%TYPE,
                              p_to_account   IN accounts.account_number%TYPE,
                              p_amount       IN NUMBER,
                              p_reference    IN VARCHAR2 DEFAULT NULL);
END bank_pkg;
/
 
CREATE OR REPLACE PACKAGE BODY bank_pkg AS
    c_max_transfer CONSTANT NUMBER := 50000;
 
    -- Private: fetch one account, or raise a clear error if it does not exist
    FUNCTION get_account (p_account IN accounts.account_number%TYPE) RETURN accounts%ROWTYPE IS
        v_account accounts%ROWTYPE;
    BEGIN
        SELECT * INTO v_account FROM accounts WHERE account_number = p_account;
        RETURN v_account;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20002, 'Account ' || p_account || ' does not exist');
    END get_account;
 
    FUNCTION balance_of (p_account IN accounts.account_number%TYPE) RETURN accounts.balance%TYPE IS
    BEGIN
        RETURN get_account(p_account).balance;
    END balance_of;
 
    PROCEDURE transfer_funds (p_from_account IN accounts.account_number%TYPE,
                              p_to_account   IN accounts.account_number%TYPE,
                              p_amount       IN NUMBER,
                              p_reference    IN VARCHAR2 DEFAULT NULL) IS
        v_from accounts%ROWTYPE;
        v_to   accounts%ROWTYPE;
        v_note transactions.description%TYPE;
    BEGIN
        SAVEPOINT before_transfer;
 
        IF p_amount IS NULL OR p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'The amount must be greater than zero');
        ELSIF p_amount > c_max_transfer THEN
            RAISE_APPLICATION_ERROR(-20006, 'Transfers above ' || TO_CHAR(c_max_transfer, 'FM999,999')
                                            || ' need branch approval');
        ELSIF p_from_account = p_to_account THEN
            RAISE_APPLICATION_ERROR(-20005, 'The two accounts must be different');
        END IF;
 
        -- Lock both rows, always in the same order, so two opposite transfers cannot deadlock
        FOR r IN (SELECT account_id FROM accounts
                  WHERE  account_number IN (p_from_account, p_to_account)
                  ORDER  BY account_number
                  FOR UPDATE) LOOP
            NULL;
        END LOOP;
 
        v_from := get_account(p_from_account);
        v_to   := get_account(p_to_account);
 
        IF v_from.status <> 'ACTIVE' OR v_to.status <> 'ACTIVE' THEN
            RAISE_APPLICATION_ERROR(-20004, 'Both accounts must be active');
        ELSIF v_from.balance < p_amount THEN
            RAISE_APPLICATION_ERROR(-20001, 'Insufficient funds: account ' || p_from_account || ' has '
                                            || TO_CHAR(v_from.balance, 'FM999,999,990.00') || ' available');
        END IF;
 
        UPDATE accounts SET balance = balance - p_amount WHERE account_id = v_from.account_id;
        UPDATE accounts SET balance = balance + p_amount WHERE account_id = v_to.account_id;
 
        v_note := SUBSTR(p_reference, 1, 150);
        INSERT INTO transactions (account_id, txn_type, amount, description, channel, txn_date)
        VALUES (v_from.account_id, 'TRANSFER_OUT', p_amount,
                NVL(v_note, 'Transfer to ' || p_to_account), 'WEB', SYSTIMESTAMP);
        INSERT INTO transactions (account_id, txn_type, amount, description, channel, txn_date)
        VALUES (v_to.account_id, 'TRANSFER_IN', p_amount,
                NVL(v_note, 'Transfer from ' || p_from_account), 'WEB', SYSTIMESTAMP);
        -- No COMMIT: the caller decides. The app commits; a test can roll back.
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO before_transfer;
            RAISE;
    END transfer_funds;
END bank_pkg;
/