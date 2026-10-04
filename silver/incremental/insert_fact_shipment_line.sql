-- =============================================================================
-- Incremental INSERT: FACT_SHIPMENT_LINE
-- Silver target: SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE
-- RAW source: SUPPLY_CHAIN_DW.RAW.SHIPMENT_LINES
-- Grain: SHIPMENT_LINE_ID
-- Strategy: Append-only — INSERT new rows not already in Silver
-- =============================================================================
-- Parameter: $BATCH_ID (set via: SET BATCH_ID = 'INCR_...';)

INSERT INTO SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE
  (SHIPMENT_LINE_ID, SHIPMENT_ID, ORDER_LINE_ID, PART_ID, SHIPPED_QTY, CREATED_AT)
SELECT
  src.SHIPMENT_LINE_ID, src.SHIPMENT_ID, src.ORDER_LINE_ID,
  src.PART_ID, src.SHIPPED_QTY, src.CREATED_AT
FROM SUPPLY_CHAIN_DW.RAW.SHIPMENT_LINES src
WHERE src.LOAD_BATCH_ID = $BATCH_ID
  AND NOT EXISTS (
    SELECT 1 FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE tgt
    WHERE tgt.SHIPMENT_LINE_ID = src.SHIPMENT_LINE_ID
  );
