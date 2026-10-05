-- ============================================================
-- REDFLAG – THE FRAUD FILES
-- SQL-Based Fraud Detection Project
-- Name: Kshithija P
-- ============================================================

USE redflag;
-- ============================================================
-- 1. VELOCITY FRAUD
-- Users with 30 or more transactions in a single day
-- ============================================================

SELECT
    user_id,
    DATE(txn_time) AS attack_date,
    COUNT(*) AS daily_txn_count
FROM transactions
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY daily_txn_count DESC;
-- ============================================================
-- 2. ROUND-AMOUNT CLUSTERING
-- Users with 15 or more exact round-amount transactions
-- ============================================================

SELECT
    user_id,
    COUNT(*) AS round_amount_txn_count
FROM transactions
WHERE amount IN (100, 200, 500, 1000, 2000, 5000, 10000)
GROUP BY user_id
HAVING COUNT(*) >= 15
ORDER BY round_amount_txn_count DESC;
-- ============================================================
-- 3. CARD TESTING
-- Users with 30 or more transactions under ₹10 in one day
-- ============================================================

SELECT
    user_id,
    DATE(txn_time) AS transaction_date,
    COUNT(*) AS small_txn_count
FROM transactions
WHERE amount < 10
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY small_txn_count DESC;
-- ============================================================
-- 4. FAILED-THEN-SUCCEEDED
-- Users with 20 or more failed transactions
-- ============================================================

SELECT
    user_id,
    COUNT(*) AS failed_txn_count
FROM transactions
WHERE status = 'FAILED'
GROUP BY user_id
HAVING COUNT(*) >= 20
ORDER BY failed_txn_count DESC;
-- ============================================================
-- 5. ODD-HOUR CONCENTRATION
-- Users with at least 80% of transactions between 2 AM and 5 AM
-- and at least 30 total transactions
-- ============================================================

SELECT
    user_id,
    COUNT(*) AS total_txn_count,
    SUM(
        CASE
            WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
            ELSE 0
        END
    ) AS odd_hour_txn_count,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS odd_hour_percentage
FROM transactions
GROUP BY user_id
HAVING COUNT(*) >= 30
   AND SUM(
        CASE
            WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
            ELSE 0
        END
   ) / COUNT(*) >= 0.80
ORDER BY odd_hour_percentage DESC;
-- ============================================================
-- 6. MULE ACCOUNTS
-- Users with 8 or more credit transactions
-- ============================================================

SELECT
    user_id,
    COUNT(*) AS credit_txn_count
FROM transactions
WHERE txn_type = 'CREDIT'
GROUP BY user_id
HAVING COUNT(*) >= 8
ORDER BY credit_txn_count DESC;
-- ============================================================
-- 6. MULE ACCOUNTS
-- Users with 8 or more credit transactions
-- ============================================================

SELECT
    user_id,
    COUNT(*) AS credit_txn_count
FROM transactions
WHERE txn_type = 'CREDIT'
GROUP BY user_id
HAVING COUNT(*) >= 8
ORDER BY credit_txn_count DESC;
-- ============================================================
-- 7. REFUND ABUSE
-- Users with 20 or more transactions and a refund ratio above 40%
-- ============================================================

SELECT
    user_id,
    COUNT(*) AS total_txn_count,
    SUM(
        CASE
            WHEN txn_type = 'REFUND' THEN 1
            ELSE 0
        END
    ) AS refund_txn_count,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN txn_type = 'REFUND' THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS refund_percentage
FROM transactions
GROUP BY user_id
HAVING COUNT(*) >= 20
   AND SUM(
        CASE
            WHEN txn_type = 'REFUND' THEN 1
            ELSE 0
        END
   ) / COUNT(*) > 0.40
ORDER BY refund_percentage DESC;
-- ============================================================
-- 8. MERCHANT COLLUSION
-- Merchants where the top 5 users account for more than 60%
-- of the merchant's total transaction value
-- ============================================================

WITH user_merchant_volume AS (
    SELECT
        merchant_id,
        user_id,
        SUM(amount) AS user_transaction_value
    FROM transactions
    GROUP BY merchant_id, user_id
),
ranked_users AS (
    SELECT
        merchant_id,
        user_id,
        user_transaction_value,
        ROW_NUMBER() OVER (
            PARTITION BY merchant_id
            ORDER BY user_transaction_value DESC
        ) AS user_rank
    FROM user_merchant_volume
),
merchant_totals AS (
    SELECT
        merchant_id,
        SUM(user_transaction_value) AS total_transaction_value
    FROM user_merchant_volume
    GROUP BY merchant_id
)
SELECT
    r.merchant_id,
    SUM(r.user_transaction_value) AS top_5_transaction_value,
    m.total_transaction_value,
    ROUND(
        100.0 * SUM(r.user_transaction_value)
        / m.total_transaction_value,
        2
    ) AS top_5_percentage
FROM ranked_users r
JOIN merchant_totals m
    ON r.merchant_id = m.merchant_id
WHERE r.user_rank <= 5
GROUP BY r.merchant_id, m.total_transaction_value
HAVING SUM(r.user_transaction_value) / m.total_transaction_value > 0.60
ORDER BY top_5_percentage DESC;
-- ============================================================
-- 9. JUST-UNDER-THRESHOLD / STRUCTURING
-- Users with 10 or more transactions of exactly ₹9,999
-- ============================================================

SELECT
    user_id,
    COUNT(*) AS threshold_txn_count
FROM transactions
WHERE amount = 9999
GROUP BY user_id
HAVING COUNT(*) >= 10
ORDER BY threshold_txn_count DESC;
-- ============================================================
-- 10. DORMANT-THEN-ACTIVE
-- Users with a 90+ day gap followed by 15+ transactions
-- ============================================================

WITH transaction_gaps AS (
    SELECT
        user_id,
        txn_time,
        LAG(txn_time) OVER (
            PARTITION BY user_id
            ORDER BY txn_time
        ) AS previous_txn_time
    FROM transactions
),
dormant_users AS (
    SELECT
        user_id,
        txn_time AS active_start
    FROM transaction_gaps
    WHERE previous_txn_time IS NOT NULL
      AND DATEDIFF(txn_time, previous_txn_time) >= 90
)
SELECT
    d.user_id,
    d.active_start,
    COUNT(t.txn_id) AS post_gap_txn_count
FROM dormant_users d
JOIN transactions t
    ON t.user_id = d.user_id
   AND t.txn_time >= d.active_start
GROUP BY d.user_id, d.active_start
HAVING COUNT(t.txn_id) >= 15
ORDER BY post_gap_txn_count DESC;

-- ============================================================
-- 11. VELOCITY SPIKE
-- Users whose peak monthly transaction count is at least
-- 5 times their average monthly transaction count
-- and the peak is at least 20 transactions
-- ============================================================

WITH monthly_transactions AS (
    SELECT
        user_id,
        YEAR(txn_time) AS txn_year,
        MONTH(txn_time) AS txn_month,
        COUNT(*) AS monthly_txn_count
    FROM transactions
    GROUP BY user_id, YEAR(txn_time), MONTH(txn_time)
),
user_statistics AS (
    SELECT
        user_id,
        AVG(monthly_txn_count) AS average_monthly_count,
        MAX(monthly_txn_count) AS peak_monthly_count
    FROM monthly_transactions
    GROUP BY user_id
)
SELECT
    user_id,
    ROUND(average_monthly_count, 2) AS average_monthly_count,
    peak_monthly_count
FROM user_statistics
WHERE peak_monthly_count >= 20
  AND peak_monthly_count >= 5 * average_monthly_count
ORDER BY peak_monthly_count DESC;
-- ============================================================
-- 12. GEOGRAPHIC IMPOSSIBILITY
-- Same user transacting in different cities within 60 minutes
-- ============================================================

WITH transaction_history AS (
    SELECT
        user_id,
        txn_time,
        city,
        LAG(city) OVER (
            PARTITION BY user_id
            ORDER BY txn_time
        ) AS previous_city,
        LAG(txn_time) OVER (
            PARTITION BY user_id
            ORDER BY txn_time
        ) AS previous_txn_time
    FROM transactions
)
SELECT
    user_id,
    previous_city,
    city AS current_city,
    previous_txn_time,
    txn_time AS current_txn_time,
    TIMESTAMPDIFF(MINUTE, previous_txn_time, txn_time) AS minutes_between
FROM transaction_history
WHERE previous_city IS NOT NULL
  AND previous_city <> city
  AND TIMESTAMPDIFF(MINUTE, previous_txn_time, txn_time) <= 60
ORDER BY minutes_between;
