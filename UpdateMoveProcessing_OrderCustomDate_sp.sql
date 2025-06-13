USE [TMW_Live]
GO

/****** Object:  StoredProcedure [dbo].[UpdateMoveProcessing_OrderCustomDate_sp]    Script Date: 1/20/2025 9:38:25 AM ******/
SET ANSI_NULLS OFF
GO

SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[UpdateMoveProcessing_OrderCustomDate_sp](
  @mov              INTEGER, 
  @CustomDateOrigin VARCHAR(60),
  @CustomDateSource VARCHAR(60)
  )
AS
/**************************************************************************************************************************************************************************
 **
 ** Parameters:
 **   Input:
 **     @mov              INTEGER
 **       - mov_number to process
 **     @CustomDateOrigin VARCHAR(60)
 **       - when PUPARR then custom date comes from first PUP that has been arrived 
 **       - when PUPDEP then custom date comes from the first PUP that has been departed
 **       - when DRPARR then custom date comes from first DRP that has been arrived 
 **       - when DRPDEP then custom date comes from the first DRP that has been departed
 **     @CustomDateSource VARCHAR(60)
 **       - when CURRENT uses the GETDATE for custom date
 **       - otherwise uses either arrival or departure date from stop depending on String2
 **
 ** Revison History:
 **   INT-106022 - RJE 03/31/2017 - Created new procedure
 **************************************************************************************************************************************************************************/
SET NOCOUNT ON;

WITH Orders AS
(
  SELECT  OH.ord_hdrnumber,
          COUNT(1) StopCount,
          SUM(CASE WHEN S.stp_status = 'DNE' THEN 1 ELSE 0 END) DoneStopCount,
          SUM(CASE WHEN S.stp_status = 'DNE' AND S.stp_type = 'PUP' THEN 1 ELSE 0 END) PickupArrivedCount,
          SUM(CASE WHEN S.stp_status = 'DNE' AND S.stp_type = 'DRP' THEN 1 ELSE 0 END) DropArrivedCount,
          SUM(CASE WHEN S.stp_departure_status = 'DNE' AND S.stp_type = 'PUP' THEN 1 ELSE 0 END) PickupDepartedCount,
          SUM(CASE WHEN S.stp_departure_status = 'DNE' AND S.stp_type = 'DRP' THEN 1 ELSE 0 END) DropDepartedCount,
          MIN(CASE WHEN S.stp_status = 'DNE' AND S.stp_type = 'PUP' THEN stp_arrivaldate ELSE CAST('99991231 00:00' AS DATETIME) END) MinPickupArriveDate,
          MIN(CASE WHEN S.stp_departure_status = 'DNE' AND S.stp_type = 'PUP' THEN stp_departuredate ELSE CAST('99991231 00:00' AS DATETIME) END) MinPickupDepartDate,
          MIN(CASE WHEN S.stp_status = 'DNE' AND S.stp_type = 'DRP' THEN stp_arrivaldate ELSE CAST('99991231 00:00' AS DATETIME) END) MinDropArriveDate,
          MIN(CASE WHEN S.stp_departure_status = 'DNE' AND S.stp_type = 'DRP' THEN stp_departuredate ELSE CAST('99991231 00:00' AS DATETIME) END) MinDropDepartDate
    FROM  orderheader OH WITH(NOLOCK)
            INNER JOIN stops S WITH(NOLOCK) ON S.ord_hdrnumber = OH.ord_hdrnumber
    WHERE  OH.ord_hdrnumber IN (SELECT  ord_hdrnumber
                              FROM  stops WITH(NOLOCK)
                              WHERE  mov_number = @mov
                                AND  ord_hdrnumber > 0)
  GROUP BY OH.ord_hdrnumber, OH.ord_complete_stamp
),
OrderCustomDates AS
(
  SELECT  O.ord_hdrnumber,
          CASE
            WHEN @CustomDateOrigin = 'PUPDEP' AND O.PickupDepartedCount > 0 THEN
              CASE 
                WHEN OH.ord_customdate IS NULL AND OH.ord_complete_stamp IS NOT NULL THEN OH.ord_complete_stamp
                WHEN @CustomDateSource = 'CURRENT' AND OH.ord_customdate IS NULL  THEN GETDATE()
                WHEN @CustomDateSource = 'CURRENT' THEN OH.ord_customdate
                WHEN @CustomDateSource = 'STOP' AND OH.ord_customdate IS NULL THEN 
                  CASE 
                    WHEN O.MinPickupDepartDate <> CAST('99991231 00:00' AS DATETIME) THEN O.MinPickupDepartDate
                  END
				WHEN @CustomDateSource = 'STOP' THEN OH.ord_customdate
                ELSE NULL
              END
            WHEN @CustomDateOrigin = 'PUPARR' AND O.PickupArrivedCount > 0 THEN
              CASE 
                WHEN OH.ord_customdate IS NULL AND OH.ord_complete_stamp IS NOT NULL THEN OH.ord_complete_stamp
                WHEN @CustomDateSource = 'CURRENT' AND OH.ord_customdate IS NULL THEN GETDATE()
                WHEN @CustomDateSource = 'CURRENT' THEN OH.ord_customdate
                WHEN @CustomDateSource = 'STOP' AND OH.ord_customdate IS NULL THEN 
                  CASE 
                    WHEN O.MinPickupArriveDate <> CAST('99991231 00:00' AS DATETIME) THEN O.MinPickupArriveDate
                  END
				WHEN @CustomDateSource = 'STOP' THEN OH.ord_customdate
                ELSE NULL
              END
            WHEN @CustomDateOrigin = 'DRPDEP' AND O.DropDepartedCount > 0 THEN
              CASE 
                WHEN OH.ord_customdate IS NULL AND OH.ord_complete_stamp IS NOT NULL THEN OH.ord_complete_stamp
                WHEN @CustomDateSource = 'CURRENT' AND OH.ord_customdate IS NULL THEN GETDATE()
                WHEN @CustomDateSource = 'CURRENT' THEN OH.ord_customdate
                WHEN @CustomDateSource = 'STOP' AND OH.ord_customdate IS NULL THEN
                  CASE 
                    WHEN O.MinDropDepartDate <> CAST('99991231 00:00' AS DATETIME) THEN O.MinDropDepartDate
                  END
				WHEN @CustomDateSource = 'STOP' THEN OH.ord_customdate
                ELSE NULL
              END
            WHEN @CustomDateOrigin = 'DRPARR' AND O.DropArrivedCount > 0 THEN
              CASE 
                WHEN OH.ord_customdate IS NULL AND OH.ord_complete_stamp IS NOT NULL THEN OH.ord_complete_stamp
                WHEN @CustomDateSource = 'CURRENT' AND OH.ord_customdate IS NULL THEN GETDATE()
                WHEN @CustomDateSource = 'CURRENT' THEN OH.ord_customdate
                WHEN @CustomDateSource = 'STOP' AND OH.ord_customdate IS NULL THEN
                  CASE 
                    WHEN O.MinDropArriveDate <> CAST('99991231 00:00' AS DATETIME) THEN O.MinDropArriveDate
                  END
				WHEN @CustomDateSource = 'STOP' THEN OH.ord_customdate
                ELSE NULL
              END
          END OrderCustomDate
    FROM  Orders O
            INNER JOIN orderheader OH WITH(NOLOCK) on OH.ord_hdrnumber = O.ord_hdrnumber
  )
  UPDATE  OH
      SET  OH.ord_customdate = OCD.OrderCustomDate
    FROM  orderheader OH
            INNER JOIN OrderCustomDates OCD ON OCD.ord_hdrnumber = OH.ord_hdrnumber
    WHERE  COALESCE(OH.ord_customdate, CAST('99991231 00:00' AS DATETIME)) <> COALESCE(OCD.OrderCustomDate, CAST('99991231 00:00' AS DATETIME))
GO


