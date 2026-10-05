-- =====================================================================
-- RedFlag — Fraud Detection Submission
-- Student: <Your Name>
-- Batch: DA-DS-1
-- =====================================================================

USE redflag;


-- =====================================================================
-- PATTERN 1 · VELOCITY FRAUD
-- What I'm looking for:
-- Users making 30 or more transactions on a single calendar day.
-- =====================================================================

SELECT
    user_id,
    DATE(txn_time) AS attack_date,
    COUNT(*) AS daily_txn_count
FROM transactions
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY daily_txn_count DESC;


-- =====================================================================
-- PATTERN 2 · ROUND-AMOUNT CLUSTERING
-- What I'm looking for:
-- Users making 15 or more transactions using common round amounts.
-- =====================================================================

SELECT
    user_id,
    COUNT(*) AS round_amount_txns,
    SUM(amount) AS total_round_amount
FROM transactions
WHERE amount IN (100, 200, 500, 1000, 2000, 5000, 10000)
GROUP BY user_id
HAVING COUNT(*) >= 15
ORDER BY round_amount_txns DESC;


-- =====================================================================
-- PATTERN 3 · CARD TESTING
-- What I'm looking for:
-- Users making 30 or more very small transactions under ₹10
-- on the same day.
-- =====================================================================

SELECT
    user_id,
    DATE(txn_time) AS attack_date,
    COUNT(*) AS small_txn_count
FROM transactions
WHERE amount < 10
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY small_txn_count DESC;


-- =====================================================================
-- PATTERN 4 · FAILED-THEN-SUCCEEDED
-- What I'm looking for:
-- Users with 20 or more failed transactions.
-- Simplified Tier-1 version.
-- =====================================================================

SELECT
    user_id,
    COUNT(*) AS failed_txn_count
FROM transactions
WHERE status = 'FAILED'
GROUP BY user_id
HAVING COUNT(*) >= 20
ORDER BY failed_txn_count DESC;


-- =====================================================================
-- PATTERN 5 · ODD-HOUR CONCENTRATION
-- What I'm looking for:
-- Users with at least 30 transactions where 80% or more occur
-- between 2 AM and 5 AM (hours 2, 3 and 4).
-- =====================================================================

SELECT
    user_id,
    COUNT(*) AS total_transactions,
    SUM(
        CASE
            WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
            ELSE 0
        END
    ) AS odd_hour_transactions,
    ROUND(
        SUM(
            CASE
                WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
                ELSE 0
            END
        ) / COUNT(*) * 100,
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


-- =====================================================================
-- PATTERN 6 · MULE ACCOUNTS
-- What I'm looking for:
-- Users with 8 or more CREDIT transactions.
-- Simplified Tier-2 version.
-- =====================================================================

SELECT
    user_id,
    COUNT(*) AS credit_transactions,
    SUM(amount) AS total_credit_amount
FROM transactions
WHERE txn_type = 'CREDIT'
GROUP BY user_id
HAVING COUNT(*) >= 8
ORDER BY credit_transactions DESC;


-- =====================================================================
-- PATTERN 7 · REFUND ABUSE
-- What I'm looking for:
-- Users with at least 20 transactions and more than 40% refunds.
-- =====================================================================

SELECT
    user_id,
    COUNT(*) AS total_transactions,
    SUM(
        CASE
            WHEN txn_type = 'REFUND' THEN 1
            ELSE 0
        END
    ) AS refund_transactions,
    ROUND(
        SUM(
            CASE
                WHEN txn_type = 'REFUND' THEN 1
                ELSE 0
            END
        ) / COUNT(*) * 100,
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


-- =====================================================================
-- PATTERN 8 · MERCHANT COLLUSION
-- What I'm looking for:
-- Merchants where the top 5 users generate more than 60% of
-- the merchant's total transaction value.
-- =====================================================================

WITH user_merchant_totals AS (
    SELECT
        merchant_id,
        user_id,
        SUM(amount) AS user_total
    FROM transactions
    GROUP BY merchant_id, user_id
),

ranked_users AS (
    SELECT
        merchant_id,
        user_id,
        user_total,
        ROW_NUMBER() OVER (
            PARTITION BY merchant_id
            ORDER BY user_total DESC
        ) AS user_rank
    FROM user_merchant_totals
),

merchant_totals AS (
    SELECT
        merchant_id,
        SUM(amount) AS merchant_total
    FROM transactions
    GROUP BY merchant_id
),

top_five_totals AS (
    SELECT
        merchant_id,
        SUM(user_total) AS top_five_total
    FROM ranked_users
    WHERE user_rank <= 5
    GROUP BY merchant_id
)

SELECT
    m.merchant_id,
    m.merchant_total,
    t.top_five_total,
    ROUND(
        t.top_five_total / m.merchant_total * 100,
        2
    ) AS top_five_percentage
FROM merchant_totals m
JOIN top_five_totals t
    ON m.merchant_id = t.merchant_id
WHERE t.top_five_total / m.merchant_total > 0.60
ORDER BY top_five_percentage DESC;


-- =====================================================================
-- PATTERN 9 · JUST-UNDER-THRESHOLD / STRUCTURING
-- What I'm looking for:
-- Users making 10 or more transactions of exactly ₹9,999.
-- =====================================================================

SELECT
    user_id,
    COUNT(*) AS threshold_transactions,
    SUM(amount) AS total_amount
FROM transactions
WHERE amount = 9999.00
GROUP BY user_id
HAVING COUNT(*) >= 10
ORDER BY threshold_transactions DESC;


-- =====================================================================
-- PATTERN 10 · DORMANT-THEN-ACTIVE
-- What I'm looking for:
-- Users having a 90+ day gap between consecutive transactions,
-- followed by at least 15 transactions.
-- =====================================================================

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

dormant_points AS (
    SELECT
        user_id,
        txn_time AS activation_time,
        previous_txn_time
    FROM transaction_gaps
    WHERE previous_txn_time IS NOT NULL
      AND TIMESTAMPDIFF(
            DAY,
            previous_txn_time,
            txn_time
          ) >= 90
),

post_dormant_activity AS (
    SELECT
        d.user_id,
        d.activation_time,
        COUNT(t.txn_id) AS transactions_after_gap
    FROM dormant_points d
    JOIN transactions t
        ON t.user_id = d.user_id
       AND t.txn_time >= d.activation_time
    GROUP BY d.user_id, d.activation_time
)

SELECT
    user_id,
    activation_time,
    transactions_after_gap
FROM post_dormant_activity
WHERE transactions_after_gap >= 15
ORDER BY transactions_after_gap DESC;


-- =====================================================================
-- PATTERN 11 · VELOCITY SPIKE
-- What I'm looking for:
-- Users whose peak monthly transaction count is at least 5 times
-- their average monthly transaction count, with a peak of 20+.
-- =====================================================================

WITH monthly_counts AS (
    SELECT
        user_id,
        DATE_FORMAT(txn_time, '%Y-%m') AS transaction_month,
        COUNT(*) AS monthly_transaction_count
    FROM transactions
    GROUP BY user_id, DATE_FORMAT(txn_time, '%Y-%m')
),

user_statistics AS (
    SELECT
        user_id,
        AVG(monthly_transaction_count) AS average_monthly_count,
        MAX(monthly_transaction_count) AS peak_monthly_count
    FROM monthly_counts
    GROUP BY user_id
)

SELECT
    user_id,
    ROUND(average_monthly_count, 2) AS average_monthly_count,
    peak_monthly_count,
    ROUND(
        peak_monthly_count / average_monthly_count,
        2
    ) AS spike_ratio
FROM user_statistics
WHERE peak_monthly_count >= 20
  AND peak_monthly_count / average_monthly_count >= 5
ORDER BY spike_ratio DESC;


-- =====================================================================
-- PATTERN 12 · GEOGRAPHIC IMPOSSIBILITY
-- What I'm looking for:
-- Users making consecutive transactions in different cities
-- within 60 minutes.
-- =====================================================================

WITH transaction_history AS (
    SELECT
        txn_id,
        user_id,
        city,
        txn_time,
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
    txn_id,
    previous_city,
    city AS current_city,
    previous_txn_time,
    txn_time,
    TIMESTAMPDIFF(
        MINUTE,
        previous_txn_time,
        txn_time
    ) AS minutes_between_transactions
FROM transaction_history
WHERE previous_city IS NOT NULL
  AND previous_city <> city
  AND TIMESTAMPDIFF(
        MINUTE,
        previous_txn_time,
        txn_time
      ) <= 60
ORDER BY minutes_between_transactions ASC;


-- =====================================================================
-- END OF REDFLAG FRAUD DETECTION PROJECT
-- =====================================================================