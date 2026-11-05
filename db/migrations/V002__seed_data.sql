-- Invented sample data: 12 branches, 600 customers, about 1,000 accounts and 60,000 transactions.
-- Every person is invented and every email address is at example.com, a domain reserved for examples.
-- DBMS_RANDOM is seeded, so every DemoBank database (CI, each server, each student) gets the same rows.
--
-- What is in it, so there is something to find on Days 2 and 3:
--   * accounts.balance always equals the account's credits minus its debits, and never goes below zero
--     at any point in its history (withdrawals that would overdraw become deposits instead)
--   * about 7% of accounts are DORMANT: no activity after 2024
--   * about 1% of deposits are unusually large (10,000 to 50,000)
--   * PENDING and REJECTED customers; REJECTED customers have no accounts
--   * no TRANSFER_IN / TRANSFER_OUT rows yet: those come from bank_pkg.transfer_funds on Day 3

INSERT INTO branches VALUES ('BR001', 'Head Office',         'London',        DATE '2005-03-01');
INSERT INTO branches VALUES ('BR002', 'Canary Wharf',        'London',        DATE '2009-06-15');
INSERT INTO branches VALUES ('BR003', 'Manhattan Midtown',   'New York',      DATE '2007-09-10');
INSERT INTO branches VALUES ('BR004', 'Brooklyn Heights',    'New York',      DATE '2014-02-03');
INSERT INTO branches VALUES ('BR005', 'Victoria Island',     'Lagos',         DATE '2010-11-22');
INSERT INTO branches VALUES ('BR006', 'Ikeja',               'Lagos',         DATE '2016-04-18');
INSERT INTO branches VALUES ('BR007', 'Westlands',           'Nairobi',       DATE '2012-08-07');
INSERT INTO branches VALUES ('BR008', 'Sandton',             'Johannesburg',  DATE '2011-01-31');
INSERT INTO branches VALUES ('BR009', 'Bay Street',          'Toronto',       DATE '2013-05-20');
INSERT INTO branches VALUES ('BR010', 'DIFC',                'Dubai',         DATE '2015-10-12');
INSERT INTO branches VALUES ('BR011', 'Raffles Place',       'Singapore',     DATE '2017-07-01');
INSERT INTO branches VALUES ('BR012', 'Digital Branch',      'Online',        DATE '2020-03-16');

DECLARE
    TYPE t_list IS TABLE OF VARCHAR2(40);

    first_names t_list := t_list(
        'Ada', 'Adebayo', 'Aisha', 'Amara', 'Ana', 'Arjun', 'Ben', 'Carlos', 'Chen', 'Chidi',
        'Chloe', 'Daniel', 'David', 'Elena', 'Emeka', 'Emma', 'Fatima', 'Grace', 'Hana', 'Hassan',
        'Ibrahim', 'Ifeoma', 'Isabel', 'James', 'Jin', 'Kemi', 'Kofi', 'Lena', 'Liam', 'Lucia',
        'Maria', 'Mei', 'Musa', 'Nadia', 'Ngozi', 'Noah', 'Olu', 'Omar', 'Priya', 'Rafael',
        'Rohan', 'Sara', 'Sipho', 'Sofia', 'Tariq', 'Thandi', 'Tomas', 'Uche', 'Wanjiru', 'Wei',
        'Yusuf', 'Zainab', 'Zanele', 'Zoe');
    last_names t_list := t_list(
        'Abara', 'Adeyemi', 'Ahmed', 'Bello', 'Brown', 'Chukwu', 'Costa', 'Dlamini', 'Eze', 'Fernandes',
        'Garcia', 'Gupta', 'Hassan', 'Ibekwe', 'Johnson', 'Kamau', 'Khan', 'Kim', 'Lee', 'Martin',
        'Mensah', 'Mohammed', 'Nair', 'Ndlovu', 'Nguyen', 'Obi', 'Odhiambo', 'Okafor', 'Okeke', 'Oyelaran',
        'Patel', 'Rossi', 'Santos', 'Schmidt', 'Silva', 'Singh', 'Smith', 'Tan', 'Taylor', 'Wang',
        'Williams', 'Wong', 'Yamamoto', 'Zulu');
    branch_codes t_list := t_list('BR001', 'BR002', 'BR003', 'BR004', 'BR005', 'BR006',
                                  'BR007', 'BR008', 'BR009', 'BR010', 'BR011', 'BR012');
    branch_cities t_list := t_list('London', 'London', 'New York', 'New York', 'Lagos', 'Lagos',
                                   'Nairobi', 'Johannesburg', 'Toronto', 'Dubai', 'Singapore', NULL);

    c_customers   CONSTANT PLS_INTEGER := 600;
    c_data_end    CONSTANT DATE := DATE '2026-10-31';
    c_dormant_end CONSTANT DATE := DATE '2024-12-31';

    v_rand        NUMBER;
    v_first       VARCHAR2(40);
    v_last        VARCHAR2(40);
    v_branch      PLS_INTEGER;
    v_city        VARCHAR2(60);
    v_kyc         customers.kyc_status%TYPE;
    v_joined      DATE;
    v_customer_id customers.customer_id%TYPE;
    v_account_id  accounts.account_id%TYPE;
    v_acct_seq    PLS_INTEGER := 0;
    v_type        accounts.account_type%TYPE;
    v_acct_branch accounts.branch_code%TYPE;
    v_status      accounts.status%TYPE;
    v_opened      DATE;
    v_last_day    DATE;
    v_txn_count   PLS_INTEGER;
    v_when        TIMESTAMP;
    v_step        NUMBER;
    v_balance     NUMBER(15,2);
    v_amount      NUMBER(15,2);
    v_txn_type    transactions.txn_type%TYPE;
    v_desc        transactions.description%TYPE;
    v_channel     transactions.channel%TYPE;

    -- A random amount between lo and hi, skewed towards small values as real payments are
    FUNCTION amount_between(lo NUMBER, hi NUMBER) RETURN NUMBER IS
    BEGIN
        RETURN ROUND(EXP(DBMS_RANDOM.VALUE(LN(lo), LN(hi))), 2);
    END;

    FUNCTION pick(list t_list) RETURN VARCHAR2 IS
    BEGIN
        RETURN list(TRUNC(DBMS_RANDOM.VALUE(1, list.COUNT + 1)));
    END;

    PROCEDURE add_txn(p_type VARCHAR2, p_amount NUMBER, p_desc VARCHAR2, p_channel VARCHAR2, p_when TIMESTAMP) IS
    BEGIN
        INSERT INTO transactions (account_id, txn_type, amount, description, channel, txn_date)
        VALUES (v_account_id, p_type, p_amount, p_desc, p_channel, p_when);
    END;
BEGIN
    DBMS_RANDOM.SEED(20261104);

    FOR i IN 1 .. c_customers LOOP
        v_first  := pick(first_names);
        v_last   := pick(last_names);
        v_branch := TRUNC(DBMS_RANDOM.VALUE(1, branch_codes.COUNT + 1));
        -- Customers of the Digital Branch live anywhere
        v_city   := NVL(branch_cities(v_branch), branch_cities(TRUNC(DBMS_RANDOM.VALUE(1, branch_cities.COUNT))));
        v_rand   := DBMS_RANDOM.VALUE;
        v_kyc    := CASE WHEN v_rand < 0.03 THEN 'REJECTED' WHEN v_rand < 0.10 THEN 'PENDING' ELSE 'VERIFIED' END;
        v_joined := DATE '2019-01-01' + TRUNC(DBMS_RANDOM.VALUE(0, DATE '2026-06-30' - DATE '2019-01-01'));

        INSERT INTO customers (full_name, email, date_of_birth, city, kyc_status, created_at)
        VALUES (v_first || ' ' || v_last,
                LOWER(v_first || '.' || v_last || '.' || i) || '@example.com',
                DATE '1950-01-01' + TRUNC(DBMS_RANDOM.VALUE(0, DATE '2006-12-31' - DATE '1950-01-01')),
                v_city, v_kyc, CAST(v_joined AS TIMESTAMP) + NUMTODSINTERVAL(DBMS_RANDOM.VALUE(8, 18), 'HOUR'))
        RETURNING customer_id INTO v_customer_id;

        CONTINUE WHEN v_kyc = 'REJECTED';

        -- One to three accounts, opened on or after the day the customer joined
        FOR a IN 1 .. TRUNC(DBMS_RANDOM.VALUE(1, 3.6)) LOOP
            v_acct_seq := v_acct_seq + 1;
            v_rand   := DBMS_RANDOM.VALUE;
            v_type   := CASE WHEN a = 1 OR v_rand < 0.55 THEN 'SAVINGS' WHEN v_rand < 0.88 THEN 'CURRENT' ELSE 'FIXED' END;
            IF a = 2 AND v_type = 'SAVINGS' THEN v_type := 'CURRENT'; END IF;
            v_opened := v_joined + TRUNC(DBMS_RANDOM.VALUE(0, LEAST(400, c_data_end - 30 - v_joined)));
            v_status := CASE WHEN v_type <> 'FIXED' AND v_opened < DATE '2024-06-30' AND DBMS_RANDOM.VALUE < 0.08
                             THEN 'DORMANT' ELSE 'ACTIVE' END;
            v_last_day := CASE v_status WHEN 'DORMANT' THEN c_dormant_end ELSE c_data_end END;
            -- First account at the customer's home branch, others anywhere
            v_acct_branch := CASE WHEN a = 1 THEN branch_codes(v_branch) ELSE pick(branch_codes) END;

            INSERT INTO accounts (account_number, customer_id, branch_code, account_type, status, opened_on)
            VALUES ('20' || LPAD(v_acct_seq, 8, '0'), v_customer_id, v_acct_branch, v_type, v_status, v_opened)
            RETURNING account_id INTO v_account_id;

            -- Opening deposit
            v_when    := CAST(v_opened AS TIMESTAMP) + NUMTODSINTERVAL(DBMS_RANDOM.VALUE(9, 16), 'HOUR');
            v_balance := CASE v_type WHEN 'FIXED' THEN amount_between(5000, 100000) ELSE amount_between(500, 20000) END;
            add_txn('DEPOSIT', v_balance, 'Opening deposit', 'BRANCH', v_when);

            IF v_type = 'FIXED' THEN
                -- Fixed deposits only earn interest, once a quarter
                v_when := ADD_MONTHS(v_when, 3);
                WHILE CAST(v_when AS DATE) <= v_last_day LOOP
                    v_amount := ROUND(v_balance * 0.0125, 2);
                    add_txn('INTEREST', v_amount, 'Quarterly interest', 'SYSTEM', v_when);
                    v_balance := v_balance + v_amount;
                    v_when := ADD_MONTHS(v_when, 3);
                END LOOP;
            ELSE
                -- Activity spread across the account's life, in date order, so the balance can be tracked
                v_txn_count := TRUNC(DBMS_RANDOM.VALUE(20, 111));
                v_step := (v_last_day - v_opened) / v_txn_count;
                FOR t IN 1 .. v_txn_count LOOP
                    v_when := v_when + NUMTODSINTERVAL(v_step * DBMS_RANDOM.VALUE(0.2, 1.8), 'DAY');
                    EXIT WHEN CAST(v_when AS DATE) > v_last_day;
                    v_rand := DBMS_RANDOM.VALUE;
                    IF v_rand < 0.35 THEN
                        v_txn_type := 'DEPOSIT';
                        v_rand := DBMS_RANDOM.VALUE;
                        IF v_rand < 0.01 THEN
                            v_amount := amount_between(10000, 50000); v_desc := 'Cash deposit'; v_channel := 'BRANCH';
                        ELSIF v_rand < 0.40 THEN
                            v_amount := amount_between(800, 6000); v_desc := 'Salary payment'; v_channel := 'SYSTEM';
                        ELSIF v_rand < 0.70 THEN
                            v_amount := amount_between(20, 2000); v_desc := 'Cash deposit';
                            v_channel := CASE WHEN DBMS_RANDOM.VALUE < 0.5 THEN 'ATM' ELSE 'BRANCH' END;
                        ELSE
                            v_amount := amount_between(20, 3000); v_desc := 'Cheque deposit'; v_channel := 'MOBILE';
                        END IF;
                    ELSIF v_rand < 0.85 THEN
                        v_txn_type := 'WITHDRAWAL';
                        v_amount := amount_between(10, 1500);
                        v_rand := DBMS_RANDOM.VALUE;
                        v_desc := CASE WHEN v_rand < 0.30 THEN 'ATM withdrawal' WHEN v_rand < 0.60 THEN 'Card payment'
                                       WHEN v_rand < 0.85 THEN 'Bill payment' ELSE 'Cash withdrawal' END;
                        v_channel := CASE WHEN v_rand < 0.30 THEN 'ATM' WHEN v_rand < 0.60 THEN 'WEB'
                                          WHEN v_rand < 0.85 THEN 'MOBILE' ELSE 'BRANCH' END;
                        IF v_amount > v_balance THEN
                            -- Never overdraw: the customer pays in instead
                            v_txn_type := 'DEPOSIT'; v_desc := 'Cash deposit'; v_channel := 'BRANCH';
                        END IF;
                    ELSIF v_rand < 0.95 THEN
                        v_txn_type := 'FEE';
                        v_rand := DBMS_RANDOM.VALUE;
                        v_amount := CASE WHEN v_rand < 0.5 THEN 2.50 WHEN v_rand < 0.8 THEN 1.00 ELSE 10.00 END;
                        v_desc := CASE WHEN v_rand < 0.5 THEN 'Monthly account fee' WHEN v_rand < 0.8 THEN 'SMS alert fee'
                                       ELSE 'Card replacement fee' END;
                        v_channel := 'SYSTEM';
                        IF v_amount > v_balance THEN CONTINUE; END IF;
                    ELSE
                        v_txn_type := 'INTEREST';
                        v_amount := GREATEST(0.01, ROUND(v_balance * 0.002, 2));
                        v_desc := 'Interest credit'; v_channel := 'SYSTEM';
                    END IF;

                    add_txn(v_txn_type, v_amount, v_desc, v_channel, v_when);
                    v_balance := v_balance + CASE WHEN v_txn_type IN ('DEPOSIT', 'INTEREST') THEN v_amount ELSE -v_amount END;
                END LOOP;
            END IF;

            UPDATE accounts SET balance = v_balance WHERE account_id = v_account_id;
        END LOOP;
    END LOOP;

    COMMIT;
END;
/
