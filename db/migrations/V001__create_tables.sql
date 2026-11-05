-- DemoBank schema. Runs as the DEMOBANK user inside FREEPDB1.
-- transactions.account_id is deliberately left without an index: Day 3 reads the
-- execution plan for an account statement, sees the full scan, and adds the index.

CREATE TABLE branches (
    branch_code  VARCHAR2(10)  PRIMARY KEY,
    branch_name  VARCHAR2(100) NOT NULL,
    city         VARCHAR2(60)  NOT NULL,
    opened_on    DATE          NOT NULL
);

CREATE TABLE customers (
    customer_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name      VARCHAR2(100) NOT NULL,
    email          VARCHAR2(150) NOT NULL UNIQUE,
    date_of_birth  DATE,
    city           VARCHAR2(60),
    kyc_status     VARCHAR2(10)  DEFAULT 'PENDING' NOT NULL
                   CHECK (kyc_status IN ('PENDING', 'VERIFIED', 'REJECTED')),
    created_at     TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL
);

CREATE TABLE accounts (
    account_id      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_number  VARCHAR2(12)  NOT NULL UNIQUE,
    customer_id     NUMBER        NOT NULL REFERENCES customers,
    branch_code     VARCHAR2(10)  NOT NULL REFERENCES branches,
    account_type    VARCHAR2(10)  NOT NULL
                    CHECK (account_type IN ('SAVINGS', 'CURRENT', 'FIXED')),
    currency        CHAR(3)       DEFAULT 'USD' NOT NULL,
    balance         NUMBER(15,2)  DEFAULT 0 NOT NULL,
    status          VARCHAR2(10)  DEFAULT 'ACTIVE' NOT NULL
                    CHECK (status IN ('ACTIVE', 'DORMANT', 'CLOSED')),
    opened_on       DATE          NOT NULL
);

CREATE TABLE transactions (
    txn_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id   NUMBER        NOT NULL REFERENCES accounts,
    txn_type     VARCHAR2(12)  NOT NULL
                 CHECK (txn_type IN ('DEPOSIT', 'WITHDRAWAL', 'TRANSFER_IN', 'TRANSFER_OUT', 'FEE', 'INTEREST')),
    amount       NUMBER(15,2)  NOT NULL CHECK (amount > 0),
    description  VARCHAR2(200),
    channel      VARCHAR2(10)  CHECK (channel IN ('BRANCH', 'ATM', 'MOBILE', 'WEB', 'SYSTEM')),
    txn_date     TIMESTAMP     NOT NULL
);
