USE [TMW_Live]
GO

/****** Object:  StoredProcedure [dbo].[update_move_light]    Script Date: 1/20/2025 9:19:28 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[update_move_light] (@mov int)
AS 
/**************************************************************************************************************************************************************************
 **
 ** Parameters:
 **   Input:
 **     @mov              INTEGER
 **       - mov_number to process
 **
 ** Revison History:
 **   INT-106022 - RJE 03/31/2017 - Created new procedure update_move_processing_sp to consolidate update_move and update_move_light 
 **                                 processing to make it simpler to keep them in sync, update_move passes 'Y' in second parameter
 **                                 which causes update_assetassignment to run.
 **************************************************************************************************************************************************************************/

EXECUTE update_move_processing_sp @mov, 'N'

RETURN 

GO


