-- =============================================================================
-- Incremental MERGE: FACT_ORDER_LINE
-- Silver target: SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE
-- RAW sources: SUPPLY_CHAIN_DW.RAW.ORDERS + SUPPLY_CHAIN_DW.RAW.ORDER_LINES
-- Grain: ORDER_LINE_ID
-- Strategy: Identify affected keys from current batch, recompute from ALL RAW
-- =============================================================================
-- Parameter: $BATCH_ID (set via: SET BATCH_ID = 'INCR_...';)

MERGE INTO SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE AS tgt
USING (
  WITH
  -- Step 1: Identify affected ORDER_IDs from this batch
  changed_order_ids AS (
    SELECT DISTINCT ORDER_ID
    FROM SUPPLY_CHAIN_DW.RAW.ORDERS
    WHERE LOAD_BATCH_ID = $BATCH_ID
  ),
  -- Step 2: Identify affected ORDER_LINE_IDs from this batch (direct changes)
  changed_ol_ids_direct AS (
    SELECT DISTINCT ORDER_LINE_ID
    FROM SUPPLY_CHAIN_DW.RAW.ORDER_LINES
    WHERE LOAD_BATCH_ID = $BATCH_ID
  ),
  -- Step 3: Identify all ORDER_LINE_IDs belonging to changed orders (cascade)
  changed_ol_ids_cascade AS (
    SELECT DISTINCT ORDER_LINE_ID
    FROM SUPPLY_CHAIN_DW.RAW.ORDER_LINES
    WHERE ORDER_ID IN (SELECT ORDER_ID FROM changed_order_ids)
  ),
  -- Step 4: Union of all affected ORDER_LINE_IDs
  all_affected_ol_ids AS (
    SELECT ORDER_LINE_ID FROM changed_ol_ids_direct
    UNION
    SELECT ORDER_LINE_ID FROM changed_ol_ids_cascade
  ),
  -- Step 5: Dedup ORDERS across ALL RAW rows for affected orders
  orders_dedup AS (
    SELECT * FROM (
      SELECT *,
        ROW_NUMBER() OVER (PARTITION BY ORDER_ID ORDER BY LAST_UPDATED_AT DESC) AS rn
      FROM SUPPLY_CHAIN_DW.RAW.ORDERS
      WHERE ORDER_ID IN (
        SELECT DISTINCT ORDER_ID FROM SUPPLY_CHAIN_DW.RAW.ORDER_LINES
        WHERE ORDER_LINE_ID IN (SELECT ORDER_LINE_ID FROM all_affected_ol_ids)
      )
    ) WHERE rn = 1
  ),
  -- Step 6: Dedup ORDER_LINES across ALL RAW rows for affected line IDs
  order_lines_dedup AS (
    SELECT * FROM (
      SELECT *,
        ROW_NUMBER() OVER (PARTITION BY ORDER_LINE_ID ORDER BY LAST_UPDATED_AT DESC) AS rn
      FROM SUPPLY_CHAIN_DW.RAW.ORDER_LINES
      WHERE ORDER_LINE_ID IN (SELECT ORDER_LINE_ID FROM all_affected_ol_ids)
    ) WHERE rn = 1
  )
  -- Step 7: Reconstruct Silver rows
  SELECT
    ol.ORDER_LINE_ID,
    ol.ORDER_ID,
    o.CUSTOMER_ID,
    o.PLANT_ID,
    ol.PART_ID,
    o.ORDER_DATE::DATE                     AS ORDER_DATE_KEY,
    o.REQUESTED_DELIVERY_DATE              AS REQUESTED_DELIVERY_DATE_KEY,
    o.ORDER_STATUS,
    ol.LINE_STATUS,
    ol.ORDERED_QTY,
    ol.UNIT_PRICE,
    ol.LINE_AMOUNT,
    o.ORDER_TOTAL,
    ol.CREATED_AT                          AS LINE_CREATED_AT,
    ol.LAST_UPDATED_AT                     AS LINE_UPDATED_AT,
    o.LAST_UPDATED_AT                      AS ORDER_UPDATED_AT
  FROM order_lines_dedup ol
  JOIN orders_dedup o ON ol.ORDER_ID = o.ORDER_ID
) AS src
ON tgt.ORDER_LINE_ID = src.ORDER_LINE_ID
WHEN MATCHED AND (src.LINE_UPDATED_AT > tgt.LINE_UPDATED_AT
                  OR src.ORDER_UPDATED_AT > tgt.ORDER_UPDATED_AT)
  THEN UPDATE SET
    tgt.ORDER_ID                    = src.ORDER_ID,
    tgt.CUSTOMER_ID                 = src.CUSTOMER_ID,
    tgt.PLANT_ID                    = src.PLANT_ID,
    tgt.PART_ID                     = src.PART_ID,
    tgt.ORDER_DATE_KEY              = src.ORDER_DATE_KEY,
    tgt.REQUESTED_DELIVERY_DATE_KEY = src.REQUESTED_DELIVERY_DATE_KEY,
    tgt.ORDER_STATUS                = src.ORDER_STATUS,
    tgt.LINE_STATUS                 = src.LINE_STATUS,
    tgt.ORDERED_QTY                 = src.ORDERED_QTY,
    tgt.UNIT_PRICE                  = src.UNIT_PRICE,
    tgt.LINE_AMOUNT                 = src.LINE_AMOUNT,
    tgt.ORDER_TOTAL                 = src.ORDER_TOTAL,
    tgt.LINE_CREATED_AT             = src.LINE_CREATED_AT,
    tgt.LINE_UPDATED_AT             = src.LINE_UPDATED_AT,
    tgt.ORDER_UPDATED_AT            = src.ORDER_UPDATED_AT
WHEN NOT MATCHED
  THEN INSERT (ORDER_LINE_ID, ORDER_ID, CUSTOMER_ID, PLANT_ID, PART_ID,
               ORDER_DATE_KEY, REQUESTED_DELIVERY_DATE_KEY, ORDER_STATUS,
               LINE_STATUS, ORDERED_QTY, UNIT_PRICE, LINE_AMOUNT, ORDER_TOTAL,
               LINE_CREATED_AT, LINE_UPDATED_AT, ORDER_UPDATED_AT)
  VALUES (src.ORDER_LINE_ID, src.ORDER_ID, src.CUSTOMER_ID, src.PLANT_ID, src.PART_ID,
          src.ORDER_DATE_KEY, src.REQUESTED_DELIVERY_DATE_KEY, src.ORDER_STATUS,
          src.LINE_STATUS, src.ORDERED_QTY, src.UNIT_PRICE, src.LINE_AMOUNT, src.ORDER_TOTAL,
          src.LINE_CREATED_AT, src.LINE_UPDATED_AT, src.ORDER_UPDATED_AT);
